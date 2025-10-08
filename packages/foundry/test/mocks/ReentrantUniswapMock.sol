// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapStables {
    function swapStableToETHBest(
        address tokenIn,
        uint256 amountIn,
        address[][] calldata paths,
        uint256 amountOutMin,
        uint256 deadline
    ) external;
}

contract ReentrantUniswapMock {
    address public WETH_ADDRESS;
    mapping(bytes32 => uint256) public pathOut;
    address public target;

    constructor(address _weth) {
        WETH_ADDRESS = _weth;
    }

    function setTarget(address _t) external {
        target = _t;
    }

    function WETH() external view returns (address) {
        return WETH_ADDRESS;
    }

    function setPathOut(address[] calldata path, uint256 out) external {
        bytes32 k = keccak256(abi.encodePacked(path));
        pathOut[k] = out;
    }

    function getAmountsOut(uint256, address[] calldata path) external view returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        bytes32 k = keccak256(abi.encodePacked(path));
        uint256 out = pathOut[k];
        amounts[0] = 0;
        amounts[1] = out;
    }

    function swapExactTokensForETH(uint256 amountIn, uint256, address[] calldata path, address to, uint256)
        external
        returns (uint256[] memory amounts)
    {
        bytes32 k = keccak256(abi.encodePacked(path));
        uint256 out = pathOut[k];
        amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = out;

        // pull tokens
        if (path.length > 0) {
            IERC20 tokenIn = IERC20(path[0]);
            tokenIn.transferFrom(msg.sender, address(this), amountIn);
        }

        // Attempt reentrant call into target (SwapStables) — this should revert due to nonReentrant
        if (target != address(0)) {
            address[][] memory dummy = new address[][](1);
            address[] memory p = new address[](2);
            p[0] = path[0];
            p[1] = WETH_ADDRESS;
            dummy[0] = p;
            // call into SwapStables.swapStableToETHBest
            ISwapStables(target).swapStableToETHBest(path[0], 1, dummy, 0, block.timestamp + 1 hours);
        }

        // send ETH to `to` if we have it
        (bool ok,) = payable(to).call{ value: out }("");
        if (!ok) revert("mock-send-failed");
    }

    receive() external payable { }
}
