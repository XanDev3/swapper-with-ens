// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RevertingUniswapMock {
    address public WETH_ADDRESS;
    mapping(bytes32 => uint256) public pathOut;
    bytes32 public badKey;

    constructor(address _weth) {
        WETH_ADDRESS = _weth;
    }

    function WETH() external view returns (address) {
        return WETH_ADDRESS;
    }

    function setPathOut(address[] calldata path, uint256 out) external {
        bytes32 k = keccak256(abi.encodePacked(path));
        pathOut[k] = out;
    }

    function setBadPath(address[] calldata path) external {
        badKey = keccak256(abi.encodePacked(path));
    }

    function getAmountsOut(uint256, address[] calldata path) external view returns (uint256[] memory amounts) {
        bytes32 k = keccak256(abi.encodePacked(path));
        if (k == badKey) revert("forced-revert");
        amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = pathOut[k];
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

        if (path.length > 0) {
            IERC20 tokenIn = IERC20(path[0]);
            tokenIn.transferFrom(msg.sender, address(this), amountIn);
        }

        (bool ok,) = payable(to).call{ value: out }("");
        require(ok, "mock-send-failed");
    }

    receive() external payable { }
}
