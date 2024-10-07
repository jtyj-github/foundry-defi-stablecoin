// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzepplin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzepplin/contracts/access/Ownable.sol";
/*
* @title Decentralized Stable Coin
* @author Justin
* Collateral: Exogenous (ETH & BTC)
* Minting: Algorithmic
* Relative Stability: Pegged to USD
*
* @notice This contract is meant to be governed by the DSCEngine. This contract is just
the ERC20 implementation of our stablecoin
*
*/

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (amount > balance) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
