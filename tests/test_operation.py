from datetime import timedelta
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
    strategy_proxy,
    angle_voter
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})
    token.approve(vault, 1_000_000_000_000, {"from": bob})
    token.approve(vault, 1_000_000_000_000, {"from": tinytim})

    # users deposit to vault
    vault.deposit(alice_amount, {"from": alice})
    vault.deposit(bob_amount, {"from": bob})
    vault.deposit(tinytim_amount, {"from": tinytim})

    utils.set_0_vault_fees()

    assert san_token.balanceOf(strategy) == 0

    # First harvest
    chain.sleep(1)
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(strategy) == 0
    assert san_token_gauge.balanceOf(strategy_proxy) == 0
    assert san_token_gauge.balanceOf(angle_voter) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    utils.mock_angle_slp_profits()
    strategy.harvest({"from": strategist})

    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one > assets_at_t

    chain.mine(1, timedelta=100)
    strategy.harvest({"from": strategist})
    chain.mine(1)

    vault.withdraw({"from": alice})
    assert token.balanceOf(alice) > alice_amount
    assert token.balanceOf(bob) == 0

    vault.withdraw({"from": bob})
    assert token.balanceOf(bob) > bob_amount

    vault.withdraw({"from": tinytim})
    assert token.balanceOf(tinytim) > tinytim_amount


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
    chain,
    strategy_proxy,
    angle_voter
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})

    vault.deposit(alice_amount, {"from": alice})

    assert san_token.balanceOf(strategy) == 0

    utils.set_0_vault_fees()

    # First harvest
    chain.sleep(1)
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(strategy) == 0
    assert san_token_gauge.balanceOf(strategy_proxy) == 0
    assert san_token_gauge.balanceOf(angle_voter) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    utils.mock_angle_slp_profits()

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
    angle_token_whale,
    live_yearn_treasury,
    strategy_proxy,
    angle_voter
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})

    vault.deposit(alice_amount, {"from": alice})

    assert san_token.balanceOf(strategy) == 0

    utils.set_0_vault_fees()

    # First harvest
    chain.sleep(1)
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(angle_voter) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    chain.sleep(10 ** 10)
    chain.mine(100)

    before_harvest_proxy_rewards_bal = angle_token.balanceOf(strategy_proxy)
    strategy.harvest({"from": strategist})

    for _ in range(5):
        angle_token.transfer(
            strategy.address, 100 * 1e18, {"from": angle_token_whale}
        )  # $100 top up
        strategy.harvest({"from": strategist})
        chain.mine(1)
        chain.sleep(1)

    after_harvest_proxyy_rewards_bal = angle_token.balanceOf(strategy_proxy)
    assert after_harvest_proxyy_rewards_bal > before_harvest_proxy_rewards_bal

    chain.mine(1)
    chain.sleep(1)
    strategy.harvest({"from": strategist})
    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one > assets_at_t

    # As a technique to simulate losses, we increase slippage
    angle_stable_master.setFeeKeeper(
        BASE_PARAMS, BASE_PARAMS, BASE_PARAMS / 1000, 0, {"from": angle_fee_manager}
    )  # set SLP slippage to 0.01% (a bip)

    chain.sleep(3600 * 24 * 2)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)

    vault.withdraw(vault.balanceOf(alice), alice.address, 100, {"from": alice})

    assert token.balanceOf(alice) > alice_amount


# We don't recieve any profit here other than angle rewards, and expect everything to work
@pytest.mark.require_network("mainnet-fork")
def test_harvest_angle_rewards(
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
    strategy_proxy,
    angle_voter
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})

    vault.deposit(alice_amount, {"from": alice})

    assert san_token.balanceOf(strategy) == 0

    utils.set_0_vault_fees()

    # First harvest
    chain.sleep(1)
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(angle_voter) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    chain.sleep(10 ** 10)
    chain.mine(100)

    before_harvest_proxy_rewards_bal = angle_token.balanceOf(strategy_proxy)
    strategy.harvest({"from": strategist})
    after_harvest_proxy_rewards_bal = angle_token.balanceOf(strategy_proxy)
    assert after_harvest_proxy_rewards_bal > before_harvest_proxy_rewards_bal

    chain.sleep(3600 * 24 * 2)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)

    strategy.harvest({"from": strategist})
    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one > assets_at_t

    vault.withdraw({"from": alice})

    assert token.balanceOf(alice) > alice_amount
