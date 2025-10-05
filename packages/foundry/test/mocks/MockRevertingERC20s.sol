// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RevertingTransferERC20 is ERC20 {
    constructor(string memory name, string memory symbol, address initialAccount, uint256 initialBalance)
        ERC20(name, symbol)
    {
        _mint(initialAccount, initialBalance);
    }

    // behave like ERC20 except transferFrom always reverts
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("transferFrom-reverted");
    }

    // helper to set balances and allowances in tests
    function transferInternal(address from, address to, uint256 value) public {
        _transfer(from, to, value);
    }

    function approveInternal(address owner, address spender, uint256 value) public {
        _approve(owner, spender, value);
    }
}

contract ApproveRevertingERC20 is ERC20 {
    constructor(string memory name, string memory symbol, address initialAccount, uint256 initialBalance)
        ERC20(name, symbol)
    {
        _mint(initialAccount, initialBalance);
    }

    // behave like ERC20 except approve always reverts
    function approve(address, uint256) public pure override returns (bool) {
        revert("approve-reverted");
    }

    // Allow tests to set allowances directly (bypassing approve)
    function approveInternal(address owner, address spender, uint256 value) public {
        _approve(owner, spender, value);
    }

    function transferInternal(address from, address to, uint256 value) public {
        _transfer(from, to, value);
    }
}
