//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    // Custom errors
    error SwapStables__TransferFromFailed();
    error SwapStables__InvalidRouter();
    error SwapStables__RouterNotConfigured();
    error SwapStables__NoPaths();
    error SwapStables__NoValidPath();
    error SwapStables__ZeroAmountIn();
    error SwapStables__EthSendFailed();
    error SwapStables__DeadlineExpired();
    error SwapStables__ApproveFailed();

    IUniswapV2Router02 public immutable uniV2; // On mainnet addr = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"

    event SwapExecuted(address indexed sender, address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    // Router is provided at construction and is immutable
    constructor(address _uniV2) Ownable(msg.sender) {
        if (_uniV2 == address(0)) revert SwapStables__InvalidRouter();
        uniV2 = IUniswapV2Router02(_uniV2);
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
        if (address(uniV2) == address(0)) revert SwapStables__RouterNotConfigured();
        if (paths.length == 0) revert SwapStables__NoPaths();

        bestOut = 0;
        bestIndex = 0;

        for (uint256 i = 0; i < paths.length; i++) {
            address[] memory p = paths[i];
            // skip invalid small paths
            if (p.length < 2) continue;
            try uniV2.getAmountsOut(amountIn, p) returns (uint256[] memory amounts) {
                uint256 out = amounts[amounts.length - 1];
                if (out > bestOut) {
                    bestOut = out;
                    bestIndex = i;
                }
            } catch {
                // ignore failing path, reverts by bestOut remaining 0
                continue;
            }
        }
        if (bestOut == 0) revert SwapStables__NoValidPath();
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
        if (amountIn == 0) revert SwapStables__ZeroAmountIn();
        if (paths.length == 0) revert SwapStables__NoPaths();
        if (address(uniV2) == address(0)) revert SwapStables__RouterNotConfigured();

        // deadline check: enforcing deadline locally in case of router failure
        if (deadline < block.timestamp) revert SwapStables__DeadlineExpired();

        // pull tokens from caller
        (bool success) = IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        if (!success) revert SwapStables__TransferFromFailed();

        // approve router (reset then set). Check return values for non-standard tokens that return false
        bool approved;
        approved = IERC20(tokenIn).approve(address(uniV2), 0);
        if (!approved) revert SwapStables__ApproveFailed();
        approved = IERC20(tokenIn).approve(address(uniV2), amountIn);
        if (!approved) revert SwapStables__ApproveFailed();

        // find best path
        (, uint256 bestIndex) = estimateBestOut(amountIn, paths);

        address[] memory bestPath = paths[bestIndex];

        // execute swap: expect last token to be ETH
        // the router will return ETH to this contract for swapExactTokensForETH
        uint256[] memory amounts =
            uniV2.swapExactTokensForETH(amountIn, amountOutMin, bestPath, address(this), deadline);

        amountOut = amounts[amounts.length - 1];

        // forward ETH to sender
        (bool sent,) = payable(msg.sender).call{ value: amountOut }(" ");
        if (!sent) revert SwapStables__EthSendFailed();

        emit SwapExecuted(msg.sender, tokenIn, amountIn, amountOut);
    }

    // receive ETH from router when swapping
    receive() external payable { }
}
