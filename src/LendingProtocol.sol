// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80);
    function decimals() external view returns (uint8);
}

contract LendingProtocol {
    // Tokens
    IERC20 public collateralToken;
    IERC20 public borrowToken;

    // Price feeds (Chainlink-style)
    AggregatorV3Interface public collateralPriceFeed;
    AggregatorV3Interface public borrowPriceFeed;

    // Accounting
    mapping(address => uint256) public collateralBalances; // in token units (18 decimals)
    mapping(address => uint256) public borrowBalances;     // in token units (18 decimals)

    // Risk parameters (scaled to 1e18)
    uint256 public constant COLLATERAL_FACTOR = 75e16;     // 0.75
    uint256 public constant LIQUIDATION_THRESHOLD = 80e16; // 0.80
    uint256 public constant LIQUIDATION_BONUS = 5e16;      // 0.05
    uint256 public constant CLOSE_FACTOR = 50e16;          // 0.50

    // Events
    event DepositCollateral(address indexed user, uint256 amount);
    event WithdrawCollateral(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed liquidator, address indexed borrower, uint256 repayAmount, uint256 collateralSeized);

    constructor(
        address _collateralToken,
        address _borrowToken,
        address _collateralPriceFeed,
        address _borrowPriceFeed
    ) {
        collateralToken = IERC20(_collateralToken);
        borrowToken = IERC20(_borrowToken);
        collateralPriceFeed = AggregatorV3Interface(_collateralPriceFeed);
        borrowPriceFeed = AggregatorV3Interface(_borrowPriceFeed);
    }

    /* ========== HELPERS ========== */

    /// Normalize Chainlink price to 18 decimals
    function getLatestPrice(AggregatorV3Interface feed) internal view returns (uint256) {
        (, int256 rawPrice, , , ) = feed.latestRoundData();
        require(rawPrice > 0, "Invalid price");
        uint8 dec = feed.decimals();
        // scale price to 1e18
        if (dec == 18) {
            return uint256(rawPrice);
        } else if (dec < 18) {
            return uint256(rawPrice) * (10 ** (18 - dec));
        } else {
            return uint256(rawPrice) / (10 ** (dec - 18));
        }
    }

    /// Convert token amount -> USD value (all results scaled to 1e18)
    /// amount is in token smallest units (e.g., 1e18 for 1 token)
    function tokenValueInUSD(AggregatorV3Interface feed, uint256 amount) internal view returns (uint256) {
        uint256 price = getLatestPrice(feed); // price has 1e18 scaling (USD per token)
        // (amount * price) / 1e18 => USD value in 1e18 units
        return (amount * price) / 1e18;
    }

    function getAccountCollateralValue(address user) public view returns (uint256) {
        return tokenValueInUSD(collateralPriceFeed, collateralBalances[user]);
    }

    function getAccountBorrowValue(address user) public view returns (uint256) {
        return tokenValueInUSD(borrowPriceFeed, borrowBalances[user]);
    }

    /// Health factor scaled to 1e18; if >1e18 safe, if <1e18 liquidatable
    function _healthFactor(address user) internal view returns (uint256) {
        uint256 debtUSD = getAccountBorrowValue(user);
        if (debtUSD == 0) return type(uint256).max;
        uint256 collUSD = getAccountCollateralValue(user);
        uint256 adjusted = (collUSD * LIQUIDATION_THRESHOLD) / 1e18;
        return (adjusted * 1e18) / debtUSD;
    }

    function isSolvent(address user) public view returns (bool) {
        uint256 debtUSD = getAccountBorrowValue(user);
        if (debtUSD == 0) return true;
        uint256 collUSD = getAccountCollateralValue(user);
        uint256 maxBorrowUSD = (collUSD * COLLATERAL_FACTOR) / 1e18;
        return debtUSD <= maxBorrowUSD;
    }

    /* ========== USER ACTIONS ========== */

    // deposit collateral
    function depositCollateral(uint256 amount) external {
        require(amount > 0, "Amount>0");
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        collateralBalances[msg.sender] += amount;
        emit DepositCollateral(msg.sender, amount);
    }

    // withdraw collateral - simulate new balance first
    function withdrawCollateral(uint256 amount) external {
        require(amount > 0, "Amount>0");
        uint256 current = collateralBalances[msg.sender];
        require(current >= amount, "Insufficient collateral");

        uint256 newCollateral = current - amount;

        // compute new collateral USD w/o writing state
        uint256 newCollateralUSD = tokenValueInUSD(collateralPriceFeed, newCollateral);
        uint256 debtUSD = getAccountBorrowValue(msg.sender);

        if (debtUSD > 0) {
            uint256 adjusted = (newCollateralUSD * LIQUIDATION_THRESHOLD) / 1e18;
            require((adjusted * 1e18) >= debtUSD, "Would become insolvent");
        }

        collateralBalances[msg.sender] = newCollateral;
        require(collateralToken.transfer(msg.sender, amount), "transfer failed");
        emit WithdrawCollateral(msg.sender, amount);
    }

    // Borrow with liquidity & collateral checks
    function borrow(uint256 amount) external {
        require(amount > 0, "Amount>0");
        uint256 available = borrowToken.balanceOf(address(this));
        require(amount <= available, "Insufficient liquidity");

        // pre-check new debt vs collateral
        uint256 newDebt = borrowBalances[msg.sender] + amount;
        uint256 debtUSD = tokenValueInUSD(borrowPriceFeed, newDebt);
        uint256 collUSD = getAccountCollateralValue(msg.sender);
        uint256 maxBorrowUSD = (collUSD * COLLATERAL_FACTOR) / 1e18;
        require(debtUSD <= maxBorrowUSD, "Insufficient collateral");

        borrowBalances[msg.sender] = newDebt;
        require(borrowToken.transfer(msg.sender, amount), "transfer failed");
        emit Borrow(msg.sender, amount);
    }

    // Repay (caller repays their own debt)
    function repay(uint256 amount) external {
        require(amount > 0, "Amount>0");
        require(borrowBalances[msg.sender] >= amount, "Repay > debt");
        require(borrowToken.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        borrowBalances[msg.sender] -= amount;
        emit Repay(msg.sender, amount);
    }

    // Liquidate an unhealthy borrower (liquidator repays up to CLOSE_FACTOR portion of debt)
    function liquidate(address borrower, uint256 repayAmount) external {
        require(repayAmount > 0, "Repay>0");
        require(!isSolvent(borrower), "Borrower solvent");

        uint256 maxClose = (borrowBalances[borrower] * CLOSE_FACTOR) / 1e18;
        require(repayAmount <= maxClose, "Exceeds close factor");

        uint256 borrowPrice = getLatestPrice(borrowPriceFeed);     // 1e18 scaled
        uint256 collateralPrice = getLatestPrice(collateralPriceFeed); // 1e18 scaled

        // USD value covered by repay: repay * borrowPrice / 1e18
        // Add liquidation bonus (1 + bonus)
        uint256 repayUSD = (repayAmount * borrowPrice) / 1e18;
        uint256 seizeValueUSD = (repayUSD * (1e18 + LIQUIDATION_BONUS)) / 1e18;

        // Convert seize USD -> collateral tokens: collateralTokens = seizeValueUSD / collateralPrice
        // scaled math: (seizeValueUSD * 1e18) / collateralPrice yields token units (1e18)
        uint256 collateralToSeize = (seizeValueUSD * 1e18) / collateralPrice;

        // cap to available collateral
        uint256 availableCollateral = collateralBalances[borrower];
        if (collateralToSeize > availableCollateral) {
            collateralToSeize = availableCollateral;
            // For simplicity we do not recompute repay amount; repay still equals requested repayAmount.
            // Production code may reduce repayAmount accordingly or handle leftover bad debt.
        }

        require(collateralToSeize > 0, "Seize amount 0");

        // transfer repay token from liquidator to protocol
        require(borrowToken.transferFrom(msg.sender, address(this), repayAmount), "repay transfer failed");

        // update borrower state and transfer collateral to liquidator
        borrowBalances[borrower] -= repayAmount;
        collateralBalances[borrower] -= collateralToSeize;
        require(collateralToken.transfer(msg.sender, collateralToSeize), "collateral transfer failed");

        emit Liquidate(msg.sender, borrower, repayAmount, collateralToSeize);
    }

}
