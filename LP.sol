pragma solidity ^0.6.12;

import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol"; // interface factorys
import "./uniswapv2/interfaces/IUniswapV2Router02.sol"; // interface factorys
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LPEvent is Context, Ownable {
    
    address internal _encoreAddress;
    address[] internal _path;
    
    constructor(address _token ,address _encore) public {
        _encoreAddress = _encore;
        initialSetup(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f, _token);
        IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _path.push(address(_encoreAddress));_path.push(router.WETH());_path.push(address(tokenAddress));
    }
    using SafeMath for uint256;
    using Address for address;
    using SafeMath for uint;
    
    IUniswapV2Router02 public uniswapRouterV2;
    IUniswapV2Factory public uniswapFactory;

    address public tokenUniswapPair;
    uint256 public contractStartTimestamp;
    
    mapping (address => uint)  public contributed;
    address public tokenAddress;
    
    event LPTokenClaimed(address dst, uint value);
    event LiquidityAddition(address indexed dst, uint value);
    
    function initialSetup(address router, address factory, address _token) internal {
        contractStartTimestamp = block.timestamp;
        uniswapRouterV2 = IUniswapV2Router02(router != address(0) ? router : 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapFactory = IUniswapV2Factory(factory != address(0) ? factory : 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
        createUniswapPairMainnet(_token, _encoreAddress);
        tokenAddress = _token;
    }

    function createUniswapPairMainnet(address _token, address _encore) public returns (address) {
        require(tokenUniswapPair == address(0), "Token: pool already created");
        tokenUniswapPair = uniswapFactory.createPair(
            address(_encore),
            address(_token)
        );
        return tokenUniswapPair;
    }
    
    function getSecondsLeftInLiquidityGenerationEvent() public view returns (uint256) {
        require(liquidityGenerationOngoing(), "Event over");
        return contractStartTimestamp.add(3 days).sub(block.timestamp);
    }

    function liquidityGenerationOngoing() public view returns (bool) {
        return contractStartTimestamp.add(30 minutes) > block.timestamp;
    }
    
    function emergencyDrain24hAfterLiquidityGenerationEventIsDone() public onlyOwner {
        require(contractStartTimestamp.add(4 days) < block.timestamp, "Liquidity generation grace period still ongoing"); // About 24h after liquidity generation happens
        IERC20 encore = IERC20(_encoreAddress);
        IERC20 token = IERC20(tokenAddress);
        encore.transfer(msg.sender, encore.balanceOf(address(this)));
        token.transfer(msg.sender, encore.balanceOf(address(this)));
    }
    
    function depositENCORE(uint256 _amount, bool agreesToTermsOutlinedInLiquidityGenerationParticipationAgreement) public {
        require(liquidityGenerationOngoing(), "Liquidity Generation Event over");
        require(agreesToTermsOutlinedInLiquidityGenerationParticipationAgreement, "No agreement provided");
        IERC20 encore = IERC20(_encoreAddress);
        encore.transferFrom(address(msg.sender), address(this), _amount);
        contributed[msg.sender] += _amount;
        emit LiquidityAddition(msg.sender, _amount);
    }
    
    function depositToken(uint256 _amount, bool agreesToTermsOutlinedInLiquidityGenerationParticipationAgreement) public {
        require(liquidityGenerationOngoing(), "Liquidity Generation Event over");
        require(agreesToTermsOutlinedInLiquidityGenerationParticipationAgreement, "No agreement provided");
        IERC20 token = IERC20(tokenAddress);
        token.transferFrom(address(msg.sender), address(this), _amount);
        contributed[msg.sender] += _amount;
        emit LiquidityAddition(msg.sender, _amount);
    }
    
    bool public LPGenerationCompleted;
    uint256 public totalLPTokensMinted;
    uint256 public totalContributed;
    uint256 public LPperUnit;
    function addLiquidityToUniswapENCORExTOKENPair() public {
        require(liquidityGenerationOngoing() == false, "Liquidity generation onging");
        require(LPGenerationCompleted == false, "Liquidity generation already finished");
        IERC20 token = IERC20(tokenAddress);
        IERC20 encore = IERC20(_encoreAddress);
        IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uint256 encoreToken = router.getAmountsOut(1e18, _path)[2].div(1000000);
        totalContributed = token.balanceOf(address(this)).div(encoreToken).add(encore.balanceOf(address(this)));
        IUniswapV2Pair pair = IUniswapV2Pair(tokenUniswapPair);
        encore.transfer(address(pair), encore.balanceOf(address(this)));
        token.transfer(address(pair), token.balanceOf(address(this)));
        pair.mint(address(this));
        totalLPTokensMinted = pair.balanceOf(address(this));
        require(totalLPTokensMinted != 0 , "LP creation failed");
        LPperUnit = totalLPTokensMinted.mul(1e18).div(totalContributed); // 1e18x for  change
        require(LPperUnit != 0 , "LP creation failed");
        LPGenerationCompleted = true;

    }
    
    function claimLPTokens() public {
        require(LPGenerationCompleted, "Event not over yet");
        require(contributed[msg.sender] > 0 , "Nothing to claim, move along");
        IUniswapV2Pair pair = IUniswapV2Pair(tokenUniswapPair);
        uint256 amountLPToTransfer = contributed[msg.sender].mul(LPperUnit).div(1e18);
        pair.transfer(msg.sender, amountLPToTransfer); // stored as 1e18x value for change
        contributed[msg.sender] = 0;
        emit LPTokenClaimed(msg.sender, amountLPToTransfer);
    }
}