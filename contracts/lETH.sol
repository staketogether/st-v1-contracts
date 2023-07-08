// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import './StakeTogether.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/utils/math/Math.sol';
import './Pool.sol';

contract lETH is AccessControl, Pausable, ReentrancyGuard, ERC20, ERC20Burnable, ERC20Permit {
  bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
  bytes32 public constant ORACLE_REWARDS_ROLE = keccak256('ORACLE_REWARDS_ROLE');

  StakeTogether public stakeTogether;
  Pool public poolContract;

  event EtherReceived(address indexed sender, uint amount);
  event SetStakeTogether(address stakeTogether);
  event SetStakeTogetherFee(uint256 fee);
  event SetPoolFee(uint256 fee);
  event AddLiquidity(address indexed user, uint256 amount);
  event RemoveLiquidity(address indexed user, uint256 amount);
  event Borrow(address indexed user, uint256 amount);
  event RepayLoan(address indexed user, uint256 amount);
  event ReDeposit(address indexed user, uint256 amount);
  event ReDepositBatch(address indexed user, uint256[] amounts);
  event SetMaxBatchSize(uint256 size);

  uint256 public liquidityFee = 0.01 ether;
  uint256 public stakeTogetherFee = 0.15 ether;
  uint256 public poolFee = 0.15 ether;
  uint256 public maxBatchSize = 100;

  function setMaxBatchSize(uint256 _size) external onlyRole(ADMIN_ROLE) {
    require(_size > 0, 'ZERO_SIZE');
    maxBatchSize = _size;
    emit SetMaxBatchSize(_size);
  }

  constructor() ERC20('ST Lending Ether', 'lETH') ERC20Permit('ST Lending Ether') {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ADMIN_ROLE, msg.sender);
  }

  receive() external payable {
    _checkExtraAmount();
    emit EtherReceived(msg.sender, msg.value);
  }

  modifier onlyStakeTogether() {
    require(msg.sender == address(stakeTogether), 'ONLY_STAKE_TOGETHER_CONTRACT');
    _;
  }

  function mint(address _to, uint256 _amount) internal whenNotPaused {
    _mint(_to, _amount);
  }

  function setStakeTogether(address _stakeTogether) external onlyRole(ADMIN_ROLE) {
    require(_stakeTogether != address(0), 'STAKE_TOGETHER_ALREADY_SET');
    stakeTogether = StakeTogether(payable(_stakeTogether));
    emit SetStakeTogether(_stakeTogether);
  }

  function setStakeTogetherFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
    require(_fee > 0, 'ZERO_FEE');
    stakeTogetherFee = _fee;
    emit SetStakeTogetherFee(_fee);
  }

  function setPoolFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
    require(_fee > 0, 'ZERO_FEE');
    stakeTogetherFee = _fee;
    emit SetPoolFee(_fee);
  }

  function addLiquidity() public payable whenNotPaused nonReentrant {
    _mint(msg.sender, msg.value);
    emit AddLiquidity(msg.sender, msg.value);
  }

  function removeLiquidity(uint256 _amount) public whenNotPaused nonReentrant {
    require(_amount > 0, 'ZERO_AMOUNT');
    require(balanceOf(msg.sender) >= _amount, 'INSUFFICIENT_lETH_BALANCE');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    _burn(msg.sender, _amount);
    payable(msg.sender).transfer(_amount);
    emit RemoveLiquidity(msg.sender, _amount);
  }

  function borrow(uint256 _amount, address _pool) public whenNotPaused nonReentrant onlyStakeTogether {
    require(_amount > 0, 'ZERO_AMOUNT');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    uint256 total = _amount + Math.mulDiv(_amount, liquidityFee, 1 ether);

    uint256 stakeTogetherShare = Math.mulDiv(total, stakeTogetherFee, 1 ether);
    uint256 poolShare = Math.mulDiv(total, poolFee, 1 ether);

    uint256 liquidityProviderShare = total - stakeTogetherShare - poolShare;

    _mint(stakeTogether.stakeTogetherFeeAddress(), stakeTogetherShare);
    _mint(_pool, poolShare);
    _mint(msg.sender, liquidityProviderShare);

    emit Borrow(msg.sender, _amount);
  }

  function repayLoan() public payable whenNotPaused nonReentrant onlyStakeTogether {
    require(msg.value > 0, 'ZERO_AMOUNT');
    require(balanceOf(msg.sender) >= msg.value, 'INSUFFICIENT_lETH_BALANCE');

    _burn(msg.sender, msg.value);
    emit RepayLoan(msg.sender, msg.value);
  }

  function reDeposit(
    uint256 _amount,
    address _pool,
    address _referral
  ) public whenNotPaused nonReentrant onlyRole(ORACLE_REWARDS_ROLE) {
    require(_amount > 0, 'ZERO_AMOUNT');
    require(balanceOf(msg.sender) >= _amount, 'INSUFFICIENT_lETH_BALANCE');
    require(address(this).balance >= _amount, 'INSUFFICIENT_ETH_BALANCE');

    _burn(msg.sender, _amount);
    stakeTogether.depositPool{ value: _amount }(_pool, _referral);
    emit ReDeposit(msg.sender, _amount);
  }

  function reDepositBatch(
    uint256[] memory _amounts,
    address[] memory _pools,
    address[] memory _referrals
  ) public whenNotPaused nonReentrant onlyRole(ORACLE_REWARDS_ROLE) {
    require(_amounts.length <= maxBatchSize, 'BATCH_SIZE_TOO_LARGE');
    require(_amounts.length == _pools.length, 'ARRAY_LENGTH_MISMATCH');
    require(_pools.length == _referrals.length, 'ARRAY_LENGTH_MISMATCH');

    for (uint i = 0; i < _amounts.length; i++) {
      require(_amounts[i] > 0, 'ZERO_AMOUNT');
      require(balanceOf(msg.sender) >= _amounts[i], 'INSUFFICIENT_lETH_BALANCE');
      require(address(this).balance >= _amounts[i], 'INSUFFICIENT_ETH_BALANCE');

      _burn(msg.sender, _amounts[i]);
      stakeTogether.depositPool{ value: _amounts[i] }(_pools[i], _referrals[i]);
    }

    emit ReDepositBatch(msg.sender, _amounts);
  }

  function _checkExtraAmount() internal {
    uint256 totalSupply = totalSupply();
    if (address(this).balance > totalSupply) {
      uint256 extraAmount = address(this).balance - totalSupply;
      _transferToStakeTogether(extraAmount);
    }
  }

  function _transferToStakeTogether(uint256 _amount) private {
    payable(address(stakeTogether)).transfer(_amount);
  }
}
