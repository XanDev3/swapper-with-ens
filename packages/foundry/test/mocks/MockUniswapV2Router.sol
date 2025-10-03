// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// A very small mock router to emulate UniswapV2 behaviour for tests.
contract MockUniswapV2Router {
    address public WETH_ADDRESS;

    // mapping of (path hash) => amounts out last element
    mapping(bytes32 => uint256) public pathOut;

    constructor(address _weth) {
        WETH_ADDRESS = _weth;
    }

    function WETH() external view returns (address) {
        return WETH_ADDRESS;
    }

    // set deterministic amount out for a path
    function setPathOut(address[] calldata path, uint256 out) external {
        bytes32 k = keccak256(abi.encodePacked(path));
        pathOut[k] = out;
    }

    function getAmountsOut(uint256, /*amountIn*/ address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](2);
        bytes32 k = keccak256(abi.encodePacked(path));
        uint256 out = pathOut[k];
        amounts[0] = 0;
        amounts[1] = out;
    }

    // For tests we assume tokenIn is an ERC20 approved to this router; we will burn/transfer tokens and send ETH to `to`.
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256, /*amountOutMin*/
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external returns (uint256[] memory amounts) {
        bytes32 k = keccak256(abi.encodePacked(path));
        uint256 out = pathOut[k];
        amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = out;

        // pull tokens from caller (msg.sender should have approved this router)
        // path[0] is tokenIn
        if (path.length > 0) {
            IERC20 tokenIn = IERC20(path[0]);
            // transfer the amountIn from the caller (SwapStables contract) to this router
            tokenIn.transferFrom(msg.sender, address(this), amountIn);
        }

        // send ETH to `to` (router must be funded in test)
        (bool ok,) = payable(to).call{ value: out }("");
        require(ok, "mock-send-failed");
    }

    // Not implemented for tests
    function swapExactTokensForTokens(uint256, uint256, address[] calldata, address, uint256)
        external
        pure
        returns (uint256[] memory)
    {
        revert("not-implemented");
    }

    // Allow router to receive ETH
    receive() external payable { }
}
