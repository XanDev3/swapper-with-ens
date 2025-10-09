//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import univ2 interface
//import DAI interface
//import USDC interface

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract SwapStables is Ownable, ReentrancyGuard {
    IUniswapV2Router02 public immutable uniV2; // On mainnet addr = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"

    event SwapExecuted(address indexed sender, address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    // Router is provided at construction and is immutable
    constructor(address _uniV2) Ownable(msg.sender) {
        require(_uniV2 != address(0), "SwapStables: INVALID_ROUTER");
        uniV2 = IUniswapV2Router02(_uniV2);
    }

    /**
     * @notice Set the Uniswap V2 router address (owner only)
     */
    // Router is immutable and set in constructor; no setter provided.

    function _calculateGas() internal view returns (uint256) {
        // simple placeholder: remaining gas * gasprice (best-effort)
        return tx.gasprice * gasleft();
    }

    /**
     * @notice Estimate best amount out among candidate paths
     * @param amountIn amount of input token
     * @param paths array of candidate paths (each is an array of addresses)
     */
    function estimateBestOut(uint256 amountIn, address[][] memory paths)
        internal
        view
        returns (uint256 bestOut, uint256 bestIndex)
    {
        require(address(uniV2) != address(0), "SwapStables: ROUTER_NOT_CONFIGURED");
        require(paths.length > 0, "SwapStables: NO_PATHS");

        bestOut = 0;
        bestIndex = 0;

        for (uint256 i = 0; i < paths.length; i++) {
            address[] memory p = paths[i];
            // skip invalid small paths
            if (p.length < 2) continue;
            // quick try/catch is not available for external view calls in solidity <0.8.10? But we assume router is well-behaved in tests
            try uniV2.getAmountsOut(amountIn, p) returns (uint256[] memory amounts) {
                uint256 out = amounts[amounts.length - 1];
                if (out > bestOut) {
                    bestOut = out;
                    bestIndex = i;
                }
            } catch {
                // ignore failing path
                continue;
            }
        }
        require(bestOut > 0, "SwapStables: NO_VALID_PATH");
    }

    /**
     * @notice Swap an ERC20 stable token for ETH using Uniswap V2, choosing the most profitable path
     * @param tokenIn input ERC20 token
     * @param amountIn amount of token to swap (caller must approve this contract)
     * @param paths candidate paths where each path is an array of token addresses (last should be WETH)
     * @param amountOutMin minimum acceptable ETH out (slippage protection)
     * @param deadline unix timestamp after which the swap will fail
     */
    function swapStableToETHBest(
        address tokenIn,
        uint256 amountIn,
        address[][] calldata paths,
        uint256 amountOutMin,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "SwapStables: ZERO_AMOUNT_IN");
        require(paths.length > 0, "SwapStables: NO_PATHS");
        require(address(uniV2) != address(0), "SwapStables: ROUTER_NOT_CONFIGURED");

        // pull tokens from caller
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // approve router
        IERC20(tokenIn).approve(address(uniV2), 0);
        IERC20(tokenIn).approve(address(uniV2), amountIn);

        // find best path
        (, uint256 bestIndex) = estimateBestOut(amountIn, paths);

        address[] memory bestPath = paths[bestIndex];

        // execute swap: expect last token to be WETH so we can receive ETH
        // the router will return ETH to this contract for swapExactTokensForETH
        uint256[] memory amounts =
            uniV2.swapExactTokensForETH(amountIn, amountOutMin, bestPath, address(this), deadline);

        amountOut = amounts[amounts.length - 1];

        // forward ETH to sender
        (bool sent,) = payable(msg.sender).call{ value: amountOut }(" ");
        require(sent, "SwapStables: ETH_SEND_FAILED");

        emit SwapExecuted(msg.sender, tokenIn, amountIn, amountOut);
    }

    // receive ETH from router when swapping
    receive() external payable { }
}
