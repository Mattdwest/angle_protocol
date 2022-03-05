# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

import pytest

from brownie import Wei, accounts, Contract, config
from brownie import StrategyAngleUSDC


@pytest.mark.require_network("mainnet-fork")
def test_sequential(
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
    angleStake,
    utils,
    angle,
):
    token.approve(vault, 1_000_000_000_000, {"from": bob})
    token.approve(vault, 1_000_000_000_000, {"from": alice})
    token.approve(vault, 1_000_000_000_000, {"from": tinytim})

    # users deposit to vault
    vault.deposit(alice_amount, {"from": alice})
    vault.deposit(bob_amount, {"from": bob})
    vault.deposit(tinytim_amount, {"from": tinytim})

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    # First harvest
    strategy.harvest({"from": strategist})

    assert angleStake.balanceOf(strategy) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    utils.mock_angle_slp_profits(angle, assets_at_t / 100)

    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one > assets_at_t

    strategy.harvest({"from": strategist})
    chain.mine(1)

    alice_vault_balance = vault.balanceOf(alice)
    vault.withdraw(alice_vault_balance, alice, 75, {"from": alice})
    assert token.balanceOf(alice) > 0
    assert token.balanceOf(bob) == 0
    # assert frax.balanceOf(strategy) > 0

    bob_vault_balance = vault.balanceOf(bob)
    vault.withdraw(bob_vault_balance, bob, 75, {"from": bob})
    assert token.balanceOf(bob) > 0
    # assert usdc.balanceOf(strategy) == 0

    tt_vault_balance = vault.balanceOf(tinytim)
    vault.withdraw(tt_vault_balance, tinytim, 75, {"from": tinytim})
    assert token.balanceOf(tinytim) > 0
    # assert usdc.balanceOf(strategy) == 0
