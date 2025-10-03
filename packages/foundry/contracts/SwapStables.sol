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
    IUniswapV2Router02 public uniV2;

    event RouterUpdated(address indexed oldRouter, address indexed newRouter);
    event SwapExecuted(address indexed sender, address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    // keep constructor parameterless for tests; router can be set by owner
    constructor() Ownable(msg.sender) {
        // owner set by Ownable
    }

    /**
     * @notice Set the Uniswap V2 router address (owner only)
     */
    function setRouter(address _uniV2) external onlyOwner {
        address old = address(uniV2);
        uniV2 = IUniswapV2Router02(_uniV2);
        emit RouterUpdated(old, _uniV2);
    }

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
        require(address(uniV2) != address(0), "router-not-set");
        require(paths.length > 0, "no-paths");

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
        require(bestOut > 0, "no-valid-path");
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
        require(amountIn > 0, "zero-amount");
        require(paths.length > 0, "no-paths");
        require(address(uniV2) != address(0), "router-not-set");

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
        require(sent, "eth-send-failed");

        emit SwapExecuted(msg.sender, tokenIn, amountIn, amountOut);
    }

    // receive ETH from router when swapping 
    receive() external payable { }
}
