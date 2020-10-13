// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol"; // for WETH
import "@nomiclabs/buidler/console.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

contract FeeApprover is OwnableUpgradeSafe {
    using SafeMath for uint256;

    function initialize(
        address _ENCOREAddress,
        address _WETHAddress,
        address _uniswapFactory
    ) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        encoreTokenAddress = _ENCOREAddress;
        WETHAddress = _WETHAddress;
        tokenETHPair = IUniswapV2Factory(_uniswapFactory).getPair(WETHAddress,encoreTokenAddress);
        feePercentX100 = 11;
        paused = true;
        sync();
        //minFinney = 5000;
    }


    address tokenETHPair;
    address tokenLINKPair;
    IUniswapV2Factory public uniswapFactory;
    address internal WETHAddress;
    address encoreTokenAddress;
    address encoreVaultAddress;
    uint8 public feePercentX100;  // max 255 = 25.5% artificial clamp
    uint256 public lastTotalSupplyOfLPTokens;
    bool paused;
    uint256 private lastSupplyOfEncoreInPair;
    uint256 private lastSupplyOfWETHInPair;
    mapping (address => bool) public voidFeeList;
    mapping (address => bool) public discountFeeList;
    mapping (address => bool) public blockedReceiverList;

    function setPaused(bool _pause) public onlyOwner {
        paused = _pause;
        sync();
    }

    function setFeeMultiplier(uint8 _feeMultiplier) public onlyOwner {
        feePercentX100 = _feeMultiplier;
    }

    function setEncoreVaultAddress(address _encoreVaultAddress) public onlyOwner {
        encoreVaultAddress = _encoreVaultAddress;
        voidFeeList[encoreVaultAddress] = true;
    }
    
    function setLINKpair(address _pair) public onlyOwner {
        tokenLINKPair = _pair;
    }

    function editVoidFeeList(address _address, bool noFee) public onlyOwner{
        voidFeeList[_address] = noFee;
    }
    
    function editDiscountFeeList(address _address, bool discFee) public onlyOwner{
        discountFeeList[_address] = discFee;
    }
    
    function editBlockedReceiverList(address _address, bool block) public onlyOwner{
        blockedReceiverList[_address] = block;
    }
    
    // uint minFinney; // 2x for $ liq amount
    // function setMinimumLiquidityToTriggerStop(uint finneyAmnt) public onlyOwner{ // 1000 = 1eth
    //     minFinney = finneyAmnt;
    // }

    // function sync() public returns (bool lastIsMint, bool lpTokenBurn) {

    //     // This will update the state of lastIsMint, when called publically
    //     // So we have to sync it before to the last LP token value.
    //     uint256 _LPSupplyOfPairTotal = IERC20(tokenUniswapPair).totalSupply();
    //     lpTokenBurn = lastTotalSupplyOfLPTokens > _LPSupplyOfPairTotal;
    //     lastTotalSupplyOfLPTokens = _LPSupplyOfPairTotal;

    //     uint256 _balanceWETH = IERC20(WETHAddress).balanceOf(tokenUniswapPair);
    //     uint256 _balanceENCORE = IERC20(encoreTokenAddress).balanceOf(tokenUniswapPair);

    //     // Do not block after small liq additions
    //     // you can only withdraw 350$ now with front running
    //     // And cant front run buys with liq add ( adversary drain )

    //     lastIsMint = _balanceENCORE > lastSupplyOfEncoreInPair && _balanceWETH > lastSupplyOfWETHInPair.add(minFinney.mul(1 finney));

    //     lastSupplyOfEncoreInPair = _balanceENCORE;
    //     lastSupplyOfWETHInPair = _balanceWETH;
    // }
    uint256 internal _LPSupplyOfPairTotal
    function sync() public {
        _LPSupplyOfPairTotal = IERC20(tokenETHPair).totalSupply().add(IERC20(tokenLINKPair).totalSupply());
    }
    
    function calculateAmountsAfterFee(
        address sender,
        address recipient, // unusued maybe use din future
        uint256 amount
        ) public  returns (uint256 transferToAmount, uint256 transferToFeeDistributorAmount)
        {
            require(paused == false, "FEE APPROVER: Transfers Paused");
            sync();


            // console.log("sender is " , sender);
            // console.log("recipient is is " , recipient, 'pair is :', tokenUniswapPair);

            // console.log("Old LP supply", lastTotalSupplyOfLPTokens);
            // console.log("Current LP supply", _LPSupplyOfPairTotal);

            if(sender == tokenETHPair || sender == tokenLINKPair) {
                require(lastTotalSupplyOfLPTokens <= _LPSupplyOfPairTotal, "Liquidity withdrawals forbidden");
                //require(lastIsMint == false, "Liquidity withdrawals forbidden");
                //require(lpTokenBurn == false, "Liquidity withdrawals forbidden");
            }
            
            require(blockedReceiverList[recipient] == false, "Blocked Recipient");

            if(sender == encoreVaultAddress || voidFeeList[sender] || voidFeeList[recipient]) { // Dont have a fee when encorevault is sending, or infinite loop
                console.log("Sending without fee");                       // And when the fee split for developers are sending
                transferToFeeDistributorAmount = 0;
                transferToAmount = amount;
            }
            else {
                if(discountFeeList[sender]) { // half fee if offered fee discount
                    console.log("Discount fee transfer");
                    transferToFeeDistributorAmount = amount.mul(feePercentX100).div(2000);
                    transferToAmount = amount.sub(transferToFeeDistributorAmount);
                } else {
                console.log("Normal fee transfer");
                transferToFeeDistributorAmount = amount.mul(feePercentX100).div(1000);
                transferToAmount = amount.sub(transferToFeeDistributorAmount);
                }
            }
            lastTotalSupplyOfLPTokens = _LPSupplyOfPairTotal;
        } 


}
