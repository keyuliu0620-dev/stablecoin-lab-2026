// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SimpleStablecoin} from "../SimpleStablecoin.sol";
import {IPriceFeed} from "./IPriceFeed.sol";

contract OverCollateralizedVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable collateral;
    SimpleStablecoin public immutable stable;
    IPriceFeed public immutable priceFeed;

    uint256 public constant RATIO_PRECISION = 100;
    uint256 public constant MIN_COLLATERAL_RATIO = 150;
    uint256 public constant LIQUIDATION_RATIO = 120;
    uint256 public constant LIQUIDATION_BONUS = 10;

    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralRedeemed(address indexed user, uint256 amount);
    event StableMinted(address indexed user, uint256 amount);
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    error ZeroAddress();
    error ZeroAmount();
    error Undercollateralized();
    error NotLiquidatable();
    error InsufficientCollateral();

    constructor(
        IERC20 collateral_,
        SimpleStablecoin stable_,
        IPriceFeed priceFeed_
    ) {
        if (
            address(collateral_) == address(0) ||
            address(stable_) == address(0) ||
            address(priceFeed_) == address(0)
        ) revert ZeroAddress();

        collateral = collateral_;
        stable = stable_;
        priceFeed = priceFeed_;
    }

    function collateralPrice() public view returns (uint256) {
        (, int256 answer,,,) = priceFeed.latestRoundData();
        if (answer <= 0) revert ZeroAmount();
        return uint256(answer);
    }

    function collateralValueOf(address user) public view returns (uint256) {
        return collateralValue(collateralOf[user]);
    }

    function collateralRatio(address user) public view returns (uint256) {
        if (debtOf[user] == 0) return type(uint256).max;
        return collateralValueOf(user) * RATIO_PRECISION / debtOf[user];
    }

    function depositCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        collateral.safeTransferFrom(msg.sender, address(this), amount);
        collateralOf[msg.sender] += amount;

        emit CollateralDeposited(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > debtOf[msg.sender]) revert InsufficientCollateral();

        debtOf[msg.sender] -= amount;
        stable.burn(msg.sender, amount);
    }

    // Ex5.1: convert 18-decimal collateral and an 8-decimal price
    // into a 6-decimal USD value.
    function collateralValue(uint256 amount) public view returns (uint256) {
        return amount * collateralPrice() / 1e20;
    }

    // Ex5.2: mint only if the resulting collateral ratio is at least 150%.
    function mintStable(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        debtOf[msg.sender] += amount;

        if (collateralRatio(msg.sender) < MIN_COLLATERAL_RATIO) {
            revert Undercollateralized();
        }

        stable.mint(msg.sender, amount);
        emit StableMinted(msg.sender, amount);
    }

    // Ex5.3: withdrawals must leave the remaining position healthy.
    function redeemCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (amount > collateralOf[msg.sender]) revert InsufficientCollateral();

        collateralOf[msg.sender] -= amount;

        if (collateralRatio(msg.sender) < MIN_COLLATERAL_RATIO) {
            revert Undercollateralized();
        }

        collateral.safeTransfer(msg.sender, amount);
        emit CollateralRedeemed(msg.sender, amount);
    }

    // Ex5.4: repay the entire debt and seize collateral including a 10% bonus.
    function liquidate(address user) external {
        if (debtOf[user] == 0 ||
            collateralRatio(user) >= LIQUIDATION_RATIO) {
            revert NotLiquidatable();
        }

        uint256 debt = debtOf[user];
        uint256 available = collateralOf[user];

        uint256 collateralToSeize =
            debt * 1e20 * (RATIO_PRECISION + LIQUIDATION_BONUS)
            / (collateralPrice() * RATIO_PRECISION);

        if (collateralToSeize > available) {
            collateralToSeize = available;
        }

        // Effects before external interactions.
        debtOf[user] = 0;
        collateralOf[user] = 0;

        stable.burn(msg.sender, debt);
        collateral.safeTransfer(msg.sender, collateralToSeize);

        emit Liquidated(user, msg.sender, debt, collateralToSeize);
    }
}
