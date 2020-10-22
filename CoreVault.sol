pragma solidity 0.6.12;


import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "./INBUNIERC20.sol";
import "@nomiclabs/buidler/console.sol";

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

// Encore Vault distributes fees equally amongst staked pools
// Have fun reading it. Hopefully it's bug-free. God bless.
contract EncoreVault is OwnableUpgradeSafe {
    using SafeMath for uint256;
    using SafeMath for uint;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many  tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of ENCOREs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accEncorePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws  tokens to a pool. Here's what happens:
        //   1. The pool's `accEncorePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.

    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of  token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. ENCOREs to distribute per block.
        uint256 accEncorePerShare; // Accumulated ENCOREs per share, times 1e12. See below.
        bool withdrawable; // Is this pool withdrawable?
        bool depositable; // Is this pool depositable?
        mapping(address => mapping(address => uint256)) allowance;
    }

    // The ENCORE TOKEN!
    INBUNIERC20 public encore;
    // Dev address.
    address public devaddr;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes  tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    
    //// pending rewards awaiting anyone to massUpdate
    uint256 public pendingRewards;

    uint256 public contractStartBlock;
    uint256 public epochCalculationStartBlock;
    uint256 public cumulativeRewardsSinceStart;
    uint256 public rewardsInThisEpoch;
    uint public epoch;
    address public ENCOREETHLPBurnAddress;
    mapping(address=>bool) public voidWithdrawList;

    // Returns fees generated since start of this contract
    function averageFeesPerBlockSinceStart() external view returns (uint averagePerBlock) {
        averagePerBlock = cumulativeRewardsSinceStart.add(rewardsInThisEpoch).div(block.number.sub(contractStartBlock));
    }

    // Returns averge fees in this epoch
    function averageFeesPerBlockEpoch() external view returns (uint256 averagePerBlock) {
        averagePerBlock = rewardsInThisEpoch.div(block.number.sub(epochCalculationStartBlock));
    }

    // For easy graphing historical epoch rewards
    mapping(uint => uint256) public epochRewards;

    //Starts a new calculation epoch
    // Because averge since start will not be accurate
    function startNewEpoch() public {
        require(epochCalculationStartBlock + 50000 < block.number, "New epoch not ready yet"); // About a week
        epochRewards[epoch] = rewardsInThisEpoch;
        cumulativeRewardsSinceStart = cumulativeRewardsSinceStart.add(rewardsInThisEpoch);
        rewardsInThisEpoch = 0;
        epochCalculationStartBlock = block.number;
        ++epoch;
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event Approval(address indexed owner, address indexed spender, uint256 _pid, uint256 value);


    function initialize(
        INBUNIERC20 _encore,
        address _devaddr,
        address superAdmin
    ) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        DEV_FEE = 1666;
        encore = _encore;
        devaddr = _devaddr;
        contractStartBlock = block.number;
        _superAdmin = superAdmin;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }



    // Add a new token pool. Can only be called by the owner.
    // Note contract owner is meant to be a governance contract allowing ENCORE governance consensus
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        bool _withdrawable,
        bool _depositable
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token,"Error pool already added");
        }

        totalAllocPoint = totalAllocPoint.add(_allocPoint);


        poolInfo.push(
            PoolInfo({
                token: _token,
                allocPoint: _allocPoint,
                accEncorePerShare: 0,
                withdrawable : _withdrawable,
                depositable : _depositable
            })
        );
    }

    // Update the given pool's ENCOREs allocation point. Can only be called by the owner.
        // Note contract owner is meant to be a governance contract allowing ENCORE governance consensus

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update the given pool's ability to withdraw tokens
    // Note contract owner is meant to be a governance contract allowing ENCORE governance consensus
    function setPoolWithdrawable(
        uint256 _pid,
        bool _withdrawable
    ) public onlyOwner {
        poolInfo[_pid].withdrawable = _withdrawable;
    }
    
    function setPoolDepositable(
        uint256 _pid,
        bool _depositable
    ) public onlyOwner {
        poolInfo[_pid].depositable = _depositable;
    }


    // Note contract owner is meant to be a governance contract allowing ENCORE governance consensus
    uint16 DEV_FEE;
    function setDevFee(uint16 _DEV_FEE) public onlyOwner {
        require(_DEV_FEE <= 2000, 'Dev fee clamped at 20%');
        DEV_FEE = _DEV_FEE;
    }
    uint256 pending_DEV_rewards;

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        console.log("Mass Updating Pools");
        uint256 length = poolInfo.length;
        uint allRewards;
        for (uint256 pid = 0; pid < length; ++pid) {
            allRewards = allRewards.add(updatePool(pid));
        }

        pendingRewards = pendingRewards.sub(allRewards);
    }
    
    function editVoidWithdrawList(address _user, bool _voidfee) public onlyOwner {
        voidWithdrawList[_user] = _voidfee;
    }

    // ----
    // Function that adds pending rewards, called by the ENCORE token.
    // ----
    uint256 private encoreBalance;
    function addPendingRewards(uint256 _) public {
        uint256 newRewards = encore.balanceOf(address(this)).sub(encoreBalance);

        if(newRewards > 0) {
            encoreBalance = encore.balanceOf(address(this)); // If there is no change the balance didn't change
            pendingRewards = pendingRewards.add(newRewards);
            rewardsInThisEpoch = rewardsInThisEpoch.add(newRewards);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) internal returns (uint256 encoreRewardWhole) {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (tokenSupply == 0) { // avoids division by 0 errors
            return 0;
        }
        encoreRewardWhole = pendingRewards // Multiplies pending rewards by allocation point of this pool and then total allocation
            .mul(pool.allocPoint)        // getting the percent of total pending rewards this pool should get
            .div(totalAllocPoint);       // we can do this because pools are only mass updated
        uint256 encoreRewardFee = encoreRewardWhole.mul(DEV_FEE).div(10000);
        uint256 encoreRewardToDistribute = encoreRewardWhole.sub(encoreRewardFee);

        pending_DEV_rewards = pending_DEV_rewards.add(encoreRewardFee);

        pool.accEncorePerShare = pool.accEncorePerShare.add(
            encoreRewardToDistribute.mul(1e12).div(tokenSupply)
        );

    }

    // Deposit  tokens to EncoreVault for ENCORE allocation.
    function deposit(uint256 _pid, uint256 _amount) public {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        require(pool.depositable == true, "Depositing into this pool is disabled");
        massUpdatePools();

        // Transfer pending tokens
        // to user
        updateAndPayOutPending(_pid, msg.sender);


        //Transfer in the amounts from user
        // save gas
        if(_amount > 0) {
            pool.token.transferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }

        user.rewardDebt = user.amount.mul(pool.accEncorePerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Test coverage
    // [x] Does user get the deposited amounts?
    // [x] Does user that its deposited for update correcty?
    // [x] Does the depositor get their tokens decreased
    function depositFor(address depositFor, uint256 _pid, uint256 _amount) public {
        // requires no allowances
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][depositFor];

        massUpdatePools();

        require(pool.depositable == true, "Depositing into this pool is disabled");
        // Transfer pending tokens
        // to user
        updateAndPayOutPending(_pid, depositFor); // Update the balances of person that amount is being deposited for

        if(_amount > 0) {
            pool.token.transferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount); // This is depositedFor address
        }

        user.rewardDebt = user.amount.mul(pool.accEncorePerShare).div(1e12); /// This is deposited for address
        emit Deposit(depositFor, _pid, _amount);

    }

    // Test coverage
    // [x] Does allowance update correctly?
    function setAllowanceForPoolToken(address spender, uint256 _pid, uint256 value) public {
        PoolInfo storage pool = poolInfo[_pid];
        pool.allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, _pid, value);
    }
    
    function setENCOREETHLPBurnAddress(address _burn) public onlyOwner {
        ENCOREETHLPBurnAddress = _burn;
    }

    // Test coverage
    // [x] Does allowance decrease?
    // [x] Do oyu need allowance
    // [x] Withdraws to correct address
    function withdrawFrom(address owner, uint256 _pid, uint256 _amount) public{

        PoolInfo storage pool = poolInfo[_pid];
        require(pool.allowance[owner][msg.sender] >= _amount, "withdraw: insufficient allowance");
        pool.allowance[owner][msg.sender] = pool.allowance[owner][msg.sender].sub(_amount);
        _withdraw(_pid, _amount, owner, msg.sender);

    }
    

    // Withdraw  tokens from EncoreVault.
    function withdraw(uint256 _pid, uint256 _amount) public {

        _withdraw(_pid, _amount, msg.sender, msg.sender);

    }
    
    function claim(uint256 _pid) public {
        _withdraw(_pid, 0, msg.sender,msg.sender);
    }
    
    // Low level withdraw function
    function _withdraw(uint256 _pid, uint256 _amount, address from, address to) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][from];

        massUpdatePools();
        updateAndPayOutPending(_pid,  from); // Update balances of from this is not withdrawal but claiming ENCORE farmed
    
        
        if(_amount > 0) {
            require(pool.withdrawable, "Withdrawing from this pool is disabled");
            user.amount = user.amount.sub(_amount, "Insufficient balance");
            if(_pid == 0) {
                if(voidWithdrawList[to] || ENCOREETHLPBurnAddress == address(0)) {
                    pool.token.transfer(address(to), _amount);
                } else {
                    pool.token.transfer(address(to), _amount.mul(95).div(100));
                    pool.token.transfer(address(ENCOREETHLPBurnAddress), _amount.mul(5).div(100));
                }
            } else {
                pool.token.transfer(address(to), _amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accEncorePerShare).div(1e12);

        emit Withdraw(to, _pid, _amount);
    }

    function updateAndPayOutPending(uint256 _pid, address from) internal {


        uint256 pending = pendingENCORE(_pid, from);

        if(pending > 0) {
            safeEncoreTransfer(from, pending);
        }

    }
    
    function pendingENCORE(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accEncorePerShare = pool.accEncorePerShare;

        return user.amount.mul(accEncorePerShare).div(1e12).sub(user.rewardDebt);
    }


    // function that lets owner/governance contract
    // approve allowance for any token inside this contract
    // This means all future UNI like airdrops are covered
    // And at the same time allows us to give allowance to strategy contracts.
    // Upcoming cYFI etc vaults strategy contracts will  se this function to manage and farm yield on value locked
    function setStrategyContractOrDistributionContractAllowance(address tokenAddress, uint256 _amount, address contractAddress) public onlySuperAdmin {
        require(isContract(contractAddress), "Recipent is not a smart contract, BAD");
        require(block.number > contractStartBlock.add(95_000), "Governance setup grace period not over"); // about 2weeks
        IERC20(tokenAddress).approve(contractAddress, _amount);
    }

    function isContract(address addr) public returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }


    // Withdraw without caring about rewards. EMERGENCY ONLY.
    // !Caution this will remove all your pending rewards!
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.withdrawable, "Withdrawing from this pool is disabled");
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.token.transfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        // No mass update dont update pending rewards
    }

    // Safe encore transfer function, just in case if rounding error causes pool to not have enough ENCOREs.
    function safeEncoreTransfer(address _to, uint256 _amount) internal {
        if(_amount == 0) return;

        uint256 encoreBal = encore.balanceOf(address(this));
        if (_amount > encoreBal) {
            console.log("transfering out for to person:", _amount);
            console.log("Balance of this address is :", encoreBal);

            encore.transfer(_to, encoreBal);
            encoreBalance = encore.balanceOf(address(this));

        } else {
            encore.transfer(_to, _amount);
            encoreBalance = encore.balanceOf(address(this));

        }

        if(pending_DEV_rewards > 0) {
            uint256 devSend = pending_DEV_rewards; // Avoid recursive loop
            pending_DEV_rewards = 0;
            safeEncoreTransfer(devaddr, devSend);
        }

    }
    
    function stakedTokens(uint256 _pid, address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    // Update dev address by the previous dev.
    function setDevFeeReciever(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }



    address private _superAdmin;

    event SuperAdminTransfered(address indexed previousOwner, address indexed newOwner);



    /**
     * @dev Returns the address of the current super admin
     */
    function superAdmin() public view returns (address) {
        return _superAdmin;
    }

    /**
     * @dev Throws if called by any account other than the superAdmin
     */
    modifier onlySuperAdmin() {
        require(_superAdmin == _msgSender(), "Super admin : caller is not super admin.");
        _;
    }

    // Assisns super admint to address 0, making it unreachable forever
    function burnSuperAdmin() public virtual onlySuperAdmin {
        emit SuperAdminTransfered(_superAdmin, address(0));
        _superAdmin = address(0);
    }

    // Super admin can transfer its powers to another address
    function newSuperAdmin(address newOwner) public virtual onlySuperAdmin {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit SuperAdminTransfered(_superAdmin, newOwner);
        _superAdmin = newOwner;
    }
}
