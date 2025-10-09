// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IWETH9 {
    function deposit() external payable;
    function approve(address guy, uint256 wad) external returns (bool);
}

contract UniswapRouterCallerTest is Test {
    // mainnet addresses (Uniswap v2 router, WETH, DAI)
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    IUniswapV2Router02 router = IUniswapV2Router02(UNISWAP_V2_ROUTER);
    IERC20 public dai = IERC20(DAI_ADDRESS);
    IWETH9 public weth = IWETH9(WETH_ADDRESS);

    uint256 public constant DEADLINE_DELTA = 1 hours;

    function setUp() public {
        // If MAINNET_RPC_URL is provided in the env, tests will use the fork.
        // Ensure the test contract has ETH to perform swaps.
        vm.deal(address(this), 10 ether);
    }

    // Allow this test contract to receive ETH when the router unwraps WETH and sends ETH to `address(this)`
    receive() external payable { }

    function testEthToDaiTradeSucceeds() public {
        uint256 deadline = block.timestamp + DEADLINE_DELTA;

        address[] memory path = new address[](2);
        path[0] = WETH_ADDRESS; // swapExactETHForTokens expects path starting with WETH when sending ETH
        path[1] = DAI_ADDRESS;

        uint256 daiBefore = dai.balanceOf(address(this));

        // perform swap: send 1 ETH and accept any non-zero amount of DAI (amountOutMin = 0)
        router.swapExactETHForTokens{ value: 1 ether }(0, path, address(this), deadline);

        uint256 daiAfter = dai.balanceOf(address(this));
        assertGt(daiAfter, daiBefore, "DAI balance should increase after ETH->DAI swap");
        console.log("DAI received:", daiAfter - daiBefore);
    }

    function testEthToDaiHighSlippageReverts() public {
        uint256 deadline = block.timestamp + DEADLINE_DELTA;

        address[] memory path = new address[](2);
        path[0] = WETH_ADDRESS;
        path[1] = DAI_ADDRESS;

        // Set an absurdly high amountOutMin to force revert
        uint256 hugeAmountOutMin = 5_000_000 ether; // very large

        vm.expectRevert();
        router.swapExactETHForTokens{ value: 1 ether }(hugeAmountOutMin, path, address(this), deadline);
    }

    function testDaiToEthTradeSucceeds() public {
        uint256 deadline = block.timestamp + DEADLINE_DELTA;

        // First, buy some DAI on the router using ETH so we have an ERC20 balance to swap back
        address[] memory pathEthToDai = new address[](2);
        pathEthToDai[0] = WETH_ADDRESS;
        pathEthToDai[1] = DAI_ADDRESS;

        // buy DAI with 1 ETH
        router.swapExactETHForTokens{ value: 1 ether }(0, pathEthToDai, address(this), deadline);

        uint256 daiBalance = dai.balanceOf(address(this));
        assertGt(daiBalance, 0, "expected to have acquired some DAI for swap back to ETH");

        // Approve router to pull DAI
        vm.prank(address(this));
        dai.approve(UNISWAP_V2_ROUTER, daiBalance);

        // Prepare path DAI -> WETH (router will unwrap to ETH via swapExactTokensForETH)
        address[] memory pathDaiToWeth = new address[](2);
        pathDaiToWeth[0] = DAI_ADDRESS;
        pathDaiToWeth[1] = WETH_ADDRESS;

        uint256 ethBalanceBefore = address(this).balance;

        router.swapExactTokensForETH(daiBalance / 2, 0, pathDaiToWeth, address(this), deadline);

        uint256 ethBalanceAfter = address(this).balance;
        assertGt(ethBalanceAfter, ethBalanceBefore, "ETH balance should increase after DAI->ETH swap");
    }

    function testDaiToEthZeroInputReverts() public {
        uint256 deadline = block.timestamp + DEADLINE_DELTA;

        // Approve arbitrary small amount for router (not used because amountIn = 0)
        vm.prank(address(this));
        dai.approve(UNISWAP_V2_ROUTER, 1 ether);

        address[] memory pathDaiToWeth = new address[](2);
        pathDaiToWeth[0] = DAI_ADDRESS;
        pathDaiToWeth[1] = WETH_ADDRESS;

        vm.expectRevert();
        // amountIn == 0 should revert in router
        router.swapExactTokensForETH(0, 0, pathDaiToWeth, address(this), deadline);
    }
}
