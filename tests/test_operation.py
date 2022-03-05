# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

import pytest

from brownie import Wei, accounts, Contract, config, ZERO_ADDRESS
from brownie import StrategyAngleUSDC


@pytest.mark.require_network("mainnet-fork")
def test_operation(
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
    san_token,
    san_token_gauge,
    utils,
    angle_stable_master,
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

    assert san_token.balanceOf(strategy) == 0

    # First harvest
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(strategy) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    utils.mock_angle_slp_profits(angle_stable_master, assets_at_t / 100)

    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one > assets_at_t

    strategy.harvest({"from": strategist})
    chain.mine(1)

    alice_vault_balance = vault.balanceOf(alice)
    vault.withdraw(alice_vault_balance, alice, 75, {"from": alice})
    assert token.balanceOf(alice) > 0
    assert token.balanceOf(bob) == 0
    # assert frax.balanceOf(strategy) > 0

    # 6 hours for pricepershare to go up
    strategy.harvest({"from": strategist})
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)

    bob_vault_balance = vault.balanceOf(bob)
    vault.withdraw(bob_vault_balance, bob, 75, {"from": bob})
    assert token.balanceOf(bob) > 0
    # assert usdc.balanceOf(strategy) == 0

    # 6 hours for pricepershare to go up
    strategy.harvest({"from": strategist})
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)

    tt_vault_balance = vault.balanceOf(tinytim)
    vault.withdraw(tt_vault_balance, tinytim, 75, {"from": tinytim})
    assert token.balanceOf(tinytim) > 0
    # assert usdc.balanceOf(strategy) == 0


@pytest.mark.require_network("mainnet-fork")
def test_lossy_strat(
    token,
    vault,
    alice,
    alice_amount,
    strategy,
    san_token,
    strategist,
    san_token_gauge,
    angle_stable_master,
    gov,
    BASE_PARAMS,
    angle_fee_manager,
    utils,
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})

    vault.deposit(alice_amount, {"from": alice})

    assert san_token.balanceOf(strategy) == 0

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    # First harvest
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(strategy) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    utils.mock_angle_slp_profits(angle_stable_master, assets_at_t / 100)

    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one > assets_at_t

    # As a technique to simulate losses, we increase slippage
    angle_stable_master.setFeeKeeper(
        BASE_PARAMS, BASE_PARAMS, BASE_PARAMS / 100, 0, {"from": angle_fee_manager}
    )  # set SLP slippage to 1%

    strategy.setEmergencyExit(
        {"from": gov}
    )  # this will pull the assets out of angle, so we'll feel the slippage
    strategy.setDoHealthCheck(False, {"from": gov})
    strategy.harvest({"from": gov})

    vault.withdraw({"from": alice})

    assert token.balanceOf(alice) < assets_at_t_plus_one
    assert token.balanceOf(alice) < alice_amount


# In this situation, we incur slippage on the exit but the ANGLE rewards should compensate for this
@pytest.mark.require_network("mainnet-fork")
def test_almost_lossy_strat(
    chain,
    token,
    vault,
    alice,
    alice_amount,
    strategy,
    san_token,
    strategist,
    san_token_gauge,
    angle_stable_master,
    gov,
    BASE_PARAMS,
    angle_fee_manager,
    utils,
    angle_token,
    live_yearn_treasury,
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})

    vault.deposit(alice_amount, {"from": alice})

    assert san_token.balanceOf(strategy) == 0

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    # First harvest
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(strategy) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    chain.sleep(10 ** 10)
    chain.mine(100)

    before_harvest_treasury_rewards_bal = angle_token.balanceOf(live_yearn_treasury)
    strategy.harvest({"from": strategist})
    after_harvest_treasury_rewards_bal = angle_token.balanceOf(live_yearn_treasury)
    assert after_harvest_treasury_rewards_bal > before_harvest_treasury_rewards_bal

    chain.mine(1)
    chain.sleep(1)
    strategy.harvest({"from": strategist})
    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one > assets_at_t

    # As a technique to simulate losses, we increase slippage
    angle_stable_master.setFeeKeeper(
        BASE_PARAMS, BASE_PARAMS, BASE_PARAMS / 10000, 0, {"from": angle_fee_manager}
    )  # set SLP slippage to 0.001% (one tenth of a bip)

    vault.withdraw({"from": alice})

    assert token.balanceOf(alice) > alice_amount
