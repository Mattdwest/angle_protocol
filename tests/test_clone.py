from brownie import Contract
import pytest


def test_clone(
    strategy,
    vault,
    strategist,
    gov,
    token,
    alice,
    alice_amount,
    bob,
    bob_amount,
    tinytim,
    tinytim_amount,
    chain,
    angleStake,
    sanToken,
    angleToken,
    uni,
    angle,
    poolManager,
):
    clone_tx = strategy.cloneAngle(
        vault,
        strategist,
        strategist,
        strategist,
        sanToken,
        angleToken,
        uni,
        angle,
        angleStake,
        poolManager,
        {"from": strategist},
    )
    cloned_strategy = Contract.from_abi(
        "StrategyAngleUSDC", clone_tx.events["Cloned"]["clone"], strategy.abi
    )

    vault.migrateStrategy(strategy.address, cloned_strategy.address, {"from": gov})
    strategy = cloned_strategy

    token.approve(vault, 1_000_000_000_000, {"from": bob})
    token.approve(vault, 1_000_000_000_000, {"from": alice})
    token.approve(vault, 1_000_000_000_000, {"from": tinytim})

    # users deposit to vault
    vault.deposit(alice_amount, {"from": alice})
    vault.deposit(bob_amount, {"from": bob})
    vault.deposit(tinytim_amount, {"from": tinytim})

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    assert sanToken.balanceOf(strategy) == 0

    # First harvest
    strategy.harvest({"from": strategist})

    assert angleStake.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 2)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)
    pps_after_first_harvest = vault.pricePerShare()

    # 6 hours for pricepershare to go up, there should be profit
    strategy.harvest({"from": gov})
    chain.sleep(3600 * 24 * 2)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)
    pps_after_second_harvest = vault.pricePerShare()
    assert pps_after_second_harvest > pps_after_first_harvest

    # 6 hours for pricepershare to go up
    strategy.harvest({"from": gov})
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)

    alice_vault_balance = vault.balanceOf(alice)
    vault.withdraw(alice_vault_balance, alice, 75, {"from": alice})
    assert token.balanceOf(alice) > 0
    assert token.balanceOf(bob) == 0
    # assert frax.balanceOf(strategy) > 0

    # 6 hours for pricepershare to go up
    strategy.harvest({"from": gov})
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)

    bob_vault_balance = vault.balanceOf(bob)
    vault.withdraw(bob_vault_balance, bob, 75, {"from": bob})
    assert token.balanceOf(bob) > 0
    # assert usdc.balanceOf(strategy) == 0

    # 6 hours for pricepershare to go up
    strategy.harvest({"from": gov})
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)

    tt_vault_balance = vault.balanceOf(tinytim)
    vault.withdraw(tt_vault_balance, tinytim, 75, {"from": tinytim})
    assert token.balanceOf(tinytim) > 0
    # assert usdc.balanceOf(strategy) == 0

    # We should have made profit
    assert vault.pricePerShare() > 1e6