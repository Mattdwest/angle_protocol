# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

import pytest

from brownie import Wei, accounts, Contract, config
from brownie import StrategyAngleUSDC


@pytest.mark.require_network("mainnet-fork")
def test_operation(
        chain,
        vault,
        strategy,
        usdc,
        usdc_liquidity,
        gov,
        rewards,
        guardian,
        strategist,
        alice,
        bob,
        tinytim,
        angleToken,
        angle,
        sanToken,
        angle_liquidity,
        angleStake,
        poolManager,
        newstrategy
):

    # Funding and vault approvals
    # Can be also done from the conftest and remove dai_liquidity from here
    usdc.approve(usdc_liquidity, 1_000_000_000000, {"from": usdc_liquidity})
    usdc.transferFrom(usdc_liquidity, gov, 300_000_000000, {"from": usdc_liquidity})
    usdc.approve(gov, 1_000_000_000000, {"from": gov})
    usdc.transferFrom(gov, bob, 1000_000000, {"from": gov})
    usdc.transferFrom(gov, alice, 4000_000000, {"from": gov})
    usdc.transferFrom(gov, tinytim, 10_000000, {"from": gov})
    usdc.approve(vault, 1_000_000_000000, {"from": bob})
    usdc.approve(vault, 1_000_000_000000, {"from": alice})
    usdc.approve(vault, 1_000_000_000000, {"from": tinytim})

       # users deposit to vault
    vault.deposit(1000_000_000, {"from": bob})
    vault.deposit(4000_000_000, {"from": alice})
    vault.deposit(10_000_000, {"from": tinytim})

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    # First harvest
    strategy.harvest({"from": gov})

    assert angleStake.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)
    pps_after_first_harvest = vault.pricePerShare()

    # 6 hours for pricepershare to go up, there should be profit
    strategy.harvest({"from": gov})
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)
    pps_after_second_harvest = vault.pricePerShare()
    assert pps_after_second_harvest > pps_after_first_harvest


    #6 hours for pricepershare to go up
    #strategy.harvest({"from": gov})
    #chain.sleep(3600 * 24 * 1)
    #chain.mine(1)
    #chain.sleep(3600 * 1)
    #chain.mine(1)

    assert angleStake.balanceOf(newstrategy) == 0

    newstrategy.setStrategist(strategist)
    vault.migrateStrategy(strategy, newstrategy, {"from": gov})

    assert sanToken.balanceOf(strategy) == 0
    assert sanToken.balanceOf(newstrategy) > 0
    assert angleToken.balanceOf(newstrategy) > 0
