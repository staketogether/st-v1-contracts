// SPDX-FileCopyrightText: 2023 Stake Together Labs <legal@staketogether.app>
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import './Fees.sol';
import './Router.sol';
import './StakeTogether.sol';

import './interfaces/IDepositContract.sol';
import './interfaces/IFees.sol';
import './interfaces/IValidators.sol';

/// @custom:security-contact security@staketogether.app
contract Validators is
  Initializable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  UUPSUpgradeable,
  ReentrancyGuardUpgradeable,
  IValidators
{
  bytes32 public constant UPGRADER_ROLE = keccak256('UPGRADER_ROLE');
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_ROLE = keccak256('ORACLE_VALIDATOR_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_MANAGER_ROLE = keccak256('ORACLE_VALIDATOR_MANAGER_ROLE');
  bytes32 public constant ORACLE_VALIDATOR_SENTINEL_ROLE = keccak256('ORACLE_VALIDATOR_SENTINEL_ROLE');

  StakeTogether public stakeTogether;
  Router public router;
  Fees public fees;
  IDepositContract public depositContract;

  address[] public validatorOracles;
  uint256 public currentOracleIndex;

  mapping(bytes => bool) public validators;
  uint256 public totalValidators;
  uint256 public validatorSize;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _depositContract, address _fees) public initializer {
    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(ADMIN_ROLE, msg.sender);
    _grantRole(UPGRADER_ROLE, msg.sender);

    depositContract = IDepositContract(_depositContract);
    fees = Fees(payable(_fees));

    totalValidators = 0;
    validatorSize = 32 ether;
  }

  function pause() public onlyRole(ADMIN_ROLE) {
    _pause();
  }

  function unpause() public onlyRole(ADMIN_ROLE) {
    _unpause();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

  receive() external payable nonReentrant {
    emit ReceiveEther(msg.sender, msg.value);
    _transferToStakeTogether();
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function setRouter(address _router) external onlyRole(ADMIN_ROLE) {
    require(_router != address(0), 'ROUTER_CONTRACT_ALREADY_SET');
    router = Router(payable(_router));
    emit SetRouter(_router);
  }

  modifier onlyRouter() {
    require(msg.sender == address(router), 'ONLY_DISTRIBUTOR_CONTRACT');
    _;
  }

  function _transferToStakeTogether() private {
    payable(address(stakeTogether)).transfer(address(this).balance);
  }

  /***********************
   ** VALIDATOR ORACLES **
   ***********************/

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

    (uint256[8] memory _shares, ) = fees.estimateFeeFixed(IFees.FeeType.StakeValidator);

    IFees.FeeRoles[8] memory roles = fees.getFeesRoles();

    for (uint i = 0; i < _shares.length - 1; i++) {
      if (_shares[i] > 0) {
        stakeTogether.mintRewards(
          fees.getFeeAddress(roles[i]),
          fees.getFeeAddress(IFees.FeeRoles.StakeTogether),
          _shares[i]
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
