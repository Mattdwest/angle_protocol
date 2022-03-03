# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

import pytest

from brownie import Wei, accounts, Contract, config
from brownie import StrategyAngleUSDC


@pytest.mark.require_network("mainnet-fork")
def test_migration(
    chain,
    vault,
    strategy,
    token,
    gov,
    strategist,
    alice,
    alice_amount,
    bob,
    bob_amount,
    tinytim,
    tinytim_amount,
    angleToken,
    angle,
    sanToken,
    angle_liquidity,
    angleStake,
    poolManager,
    newstrategy,
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})
    token.approve(vault, 1_000_000_000_000, {"from": bob})
    token.approve(vault, 1_000_000_000_000, {"from": tinytim})

    # users deposit to vault
    vault.deposit(alice_amount, {"from": alice})
    vault.deposit(bob_amount, {"from": bob})
    vault.deposit(tinytim_amount, {"from": tinytim})

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    # First harvest
    chain.sleep(1)
    strategy.harvest({"from": strategist})

    assert angleStake.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)
    pps_after_first_harvest = vault.pricePerShare()

    # 6 hours for pricepershare to go up, there should be profit
    strategy.harvest({"from": strategist})
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)
    pps_after_second_harvest = vault.pricePerShare()
    assert pps_after_second_harvest > pps_after_first_harvest

    # 6 hours for pricepershare to go up
    # strategy.harvest({"from": gov})
    # chain.sleep(3600 * 24 * 1)
    # chain.mine(1)
    # chain.sleep(3600 * 1)
    # chain.mine(1)

    assert angleStake.balanceOf(newstrategy) == 0

    newstrategy.setStrategist(strategist)
    vault.migrateStrategy(strategy, newstrategy, {"from": gov})

    assert sanToken.balanceOf(strategy) == 0
    assert sanToken.balanceOf(newstrategy) > 0
