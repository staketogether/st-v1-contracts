// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './StakeTogether.sol';
import './Router.sol';
import './Fees.sol';
import './interfaces/IDepositContract.sol';

/// @custom:security-contact security@staketogether.app
contract Validators is
  Initializable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_ROLE = keccak256('ORACLE_VALIDATOR_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_MANAGER_ROLE = keccak256('ORACLE_VALIDATOR_MANAGER_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_SENTINEL_ROLE = keccak256('ORACLE_VALIDATOR_SENTINEL_ROLE');

  StakeTogether public stakeTogether;
  Router public routerContract;
  Fees public feesContract;
  IDepositContract public depositContract;

  bool public enableBorrow = true;

  event ReceiveEther(address indexed sender, uint amount);
  event FallbackEther(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event SetRouterContract(address routerContract);
  event AddValidatorOracle(address indexed account);
  event RemoveValidatorOracle(address indexed account);
  event CreateValidator(
    address indexed creator,
    uint256 indexed amount,
    bytes publicKey,
    bytes withdrawalCredentials,
    bytes signature,
    bytes32 depositDataRoot
  );
  event RemoveValidator(address indexed account, uint256 epoch, bytes publicKey);
  event SetValidatorSize(uint256 newValidatorSize);

  constructor() {
    _disableInitializers();
  }

  function initialize(address _depositContract, address _feesContract) public initializer {
    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);

    depositContract = IDepositContract(_depositContract);
    feesContract = Fees(payable(_feesContract));
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  receive() external payable {
    _transferToStakeTogether();
    emit ReceiveEther(msg.sender, msg.value);
  }

  fallback() external payable {
    _transferToStakeTogether();
    emit FallbackEther(msg.sender, msg.value);
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function setRouterContract(address _routerContract) external onlyRole(ADMIN_ROLE) {
    require(_routerContract != address(0), 'ROUTER_CONTRACT_ALREADY_SET');
    routerContract = Router(payable(_routerContract));
    emit SetRouterContract(_routerContract);
  }

  modifier onlyRouter() {
    require(msg.sender == address(routerContract), 'ONLY_DISTRIBUTOR_CONTRACT');
    _;
  }

  function _transferToStakeTogether() private {
    payable(address(stakeTogether)).transfer(address(this).balance);
  }

  /***********************
   ** VALIDATOR ORACLES **
   ***********************/

  address[] public validatorOracles;
  uint256 public currentOracleIndex;

  modifier onlyValidatorOracle() {
    require(hasRole(ORACLE_VALIDATOR_ROLE, msg.sender), 'MISSING_ORACLE_VALIDATOR_ROLE');
    require(msg.sender == validatorOracles[currentOracleIndex], 'NOT_CURRENT_VALIDATOR_ORACLE');
    _;
  }

  function addValidatorOracle(address _oracleAddress) external onlyRole(ORACLE_VALIDATOR_MANAGER_ROLE) {
    _grantRole(ORACLE_VALIDATOR_ROLE, _oracleAddress);
    validatorOracles.push(_oracleAddress);
    emit AddValidatorOracle(_oracleAddress);
  }

  function removeValidatorOracle(
    address _oracleAddress
  ) external onlyRole(ORACLE_VALIDATOR_MANAGER_ROLE) {
    _revokeRole(ORACLE_VALIDATOR_ROLE, _oracleAddress);
    for (uint256 i = 0; i < validatorOracles.length; i++) {
      if (validatorOracles[i] == _oracleAddress) {
        validatorOracles[i] = validatorOracles[validatorOracles.length - 1];
        validatorOracles.pop();
        break;
      }
    }
    emit RemoveValidatorOracle(_oracleAddress);
  }

  function forceNextValidatorOracle() external onlyRole(ORACLE_VALIDATOR_SENTINEL_ROLE) {
    require(
      hasRole(ORACLE_VALIDATOR_SENTINEL_ROLE, msg.sender) ||
        hasRole(ORACLE_VALIDATOR_MANAGER_ROLE, msg.sender),
      'MISSING_SENDER_ROLE'
    );
    require(validatorOracles.length > 0, 'NO_VALIDATOR_ORACLE');
    _nextValidatorOracle();
  }

  function currentValidatorOracle() external view returns (address) {
    return validatorOracles[currentOracleIndex];
  }

  function isValidatorOracle(address _oracleAddress) external view returns (bool) {
    return
      hasRole(ORACLE_VALIDATOR_ROLE, _oracleAddress) &&
      validatorOracles[currentOracleIndex] == _oracleAddress;
  }

  function _nextValidatorOracle() internal {
    require(validatorOracles.length > 1, 'NOT_ENOUGH_ORACLES');
    currentOracleIndex = (currentOracleIndex + 1) % validatorOracles.length;
  }

  /*****************
   ** VALIDATORS **
   *****************/

  mapping(bytes => bool) public validators;
  uint256 public totalValidators = 0;
  uint256 public validatorSize = 32 ether;

  function createValidator(
    bytes calldata _publicKey,
    bytes calldata _withdrawalCredentials,
    bytes calldata _signature,
    bytes32 _depositDataRoot
  ) external payable nonReentrant {
    require(msg.sender == address(stakeTogether));
    require(!validators[_publicKey]);

    validators[_publicKey] = true;
    totalValidators++;

    uint256[8] memory feeAmounts = feesContract.estimateFeeFixed(Fees.FeeType.StakeValidator);

    Fees.FeeRoles[8] memory roles = feesContract.getFeesRoles();

    for (uint i = 0; i < feeAmounts.length - 1; i++) {
      if (feeAmounts[i] > 0) {
        stakeTogether.mintRewards(
          feesContract.getFeeAddress(roles[i]),
          feesContract.getFeeAddress(Fees.FeeRoles.StakeTogether),
          feeAmounts[i]
        );
      }
    }

    uint256 newBeaconBalance = stakeTogether.beaconBalance() + validatorSize;
    stakeTogether.setBeaconBalance(newBeaconBalance);

    _nextValidatorOracle();

    emit CreateValidator(
      msg.sender,
      validatorSize,
      _publicKey,
      _withdrawalCredentials,
      _signature,
      _depositDataRoot
    );

    depositContract.deposit{ value: validatorSize }(
      _publicKey,
      _withdrawalCredentials,
      _signature,
      _depositDataRoot
    );
  }

  function removeValidator(
    uint256 _epoch,
    bytes calldata _publicKey
  ) external payable nonReentrant onlyRouter {
    require(validators[_publicKey], 'PUBLIC_KEY_NOT_FOUND');

    validators[_publicKey] = false;
    totalValidators--;

    emit RemoveValidator(msg.sender, _epoch, _publicKey);
  }

  function setValidatorSize(uint256 _newSize) external onlyRole(ADMIN_ROLE) {
    require(_newSize >= 32 ether, 'MINIMUM_VALIDATOR_SIZE');
    validatorSize = _newSize;
    emit SetValidatorSize(_newSize);
  }

  function isValidator(bytes memory _publicKey) public view returns (bool) {
    return validators[_publicKey];
  }
}
