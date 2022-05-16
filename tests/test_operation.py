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
    veangle_token
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

    assert san_token_gauge.balanceOf(strategy) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    utils.mock_angle_slp_profits()
    strategy.harvest({"from": strategist})

    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one > assets_at_t
    assert veangle_token.balanceOf(strategy) > 0

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
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})

    vault.deposit(alice_amount, {"from": alice})

    assert san_token.balanceOf(strategy) == 0

    utils.set_0_vault_fees()

    # First harvest
    chain.sleep(1)
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(strategy) > 0
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
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})

    vault.deposit(alice_amount, {"from": alice})

    assert san_token.balanceOf(strategy) == 0

    utils.set_0_vault_fees()

    # First harvest
    chain.sleep(1)
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(strategy) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    chain.sleep(10 ** 5)
    chain.mine(100)

    before_harvest_treasury_rewards_bal = angle_token.balanceOf(live_yearn_treasury)
    strategy.harvest({"from": strategist})

    for _ in range(5):
        angle_token.transfer(
            strategy.address, 100 * 1e18, {"from": angle_token_whale}
        )  # $100 top up
        strategy.harvest({"from": strategist})
        chain.mine(1)
        chain.sleep(1)

    after_harvest_treasury_rewards_bal = angle_token.balanceOf(live_yearn_treasury)
    assert after_harvest_treasury_rewards_bal > before_harvest_treasury_rewards_bal

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
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})

    vault.deposit(alice_amount, {"from": alice})

    assert san_token.balanceOf(strategy) == 0

    utils.set_0_vault_fees()

    # First harvest
    chain.sleep(1)
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(strategy) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    chain.sleep(10 ** 5)
    chain.mine(100)

    before_harvest_treasury_rewards_bal = angle_token.balanceOf(live_yearn_treasury)
    strategy.harvest({"from": strategist})
    after_harvest_treasury_rewards_bal = angle_token.balanceOf(live_yearn_treasury)
    assert after_harvest_treasury_rewards_bal > before_harvest_treasury_rewards_bal

    chain.sleep(3600 * 24 * 2)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)

    strategy.harvest({"from": strategist})
    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one > assets_at_t

    vault.withdraw({"from": alice})

    assert token.balanceOf(alice) > alice_amount

@pytest.mark.require_network("mainnet-fork")
def test_veAngle_dynamics(
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
    veangle_token
):
    WEEK = 7 * 86_400
    token.approve(vault, 1_000_000_000_000, {"from": alice})

    vault.deposit(alice_amount, {"from": alice})

    assert san_token.balanceOf(strategy) == 0

    utils.set_0_vault_fees()

    # First harvest
    chain.sleep(1)
    strategy.harvest({"from": strategist})
    
    # We need some Angle in the strat
    utils.mock_angle_slp_profits()

    prev_angle_balance_treasury = angle_token.balanceOf(live_yearn_treasury)
    chain.mine(1, timedelta=1)
    tx = strategy.harvest({"from": strategist})

    collected_angle = san_token_gauge.claimed_reward(strategy, angle_token)
    angle_treasury = int(strategy.percentKeep() * collected_angle / 1e4)
    angle_sell = int(strategy.percentSell() * collected_angle / 1e4)
    angle_lock = collected_angle - angle_sell - angle_treasury

    # Check percentKeep has gone to treasury
    assert (angle_token.balanceOf(live_yearn_treasury) - \
        prev_angle_balance_treasury) == angle_treasury
    # Check that percentSell been swapped
    assert tx.events["Swap"][0]["amount0In"] == angle_sell
    # Check that the rest is locked
    assert veangle_token.balanceOf(strategy) > 0
    assert veangle_token.locked(strategy)[0] == angle_lock
    assert veangle_token.locked(strategy)[1] == int((chain.time() + strategy.timeToLock()) / WEEK) * WEEK

    previous_locked = angle_lock
    previous_time = veangle_token.locked(strategy)[1]

    # Go to near of the end of lock and ensure we can increase amount locked
    chain.mine(1, timestamp=veangle_token.locked(strategy)[1] - 100)
    tx = strategy.harvest({"from": strategist})

    locked_balance = veangle_token.locked(strategy)[0]
    assert locked_balance > angle_lock
    assert previous_time == veangle_token.locked(strategy)[1]
    
    # Go to end of lock and ensure we can withdraw
    chain.mine(1, timestamp=veangle_token.locked(strategy)[1] + 1)
    # Escrow Angle for a year now
    strategy.setTimeToLock(365 * 86_400, {"from":gov})
    tx = strategy.harvest({"from": strategist})
    # Amount withdrawn is amount locked previously
    assert tx.events["Withdraw"]["value"] == locked_balance
    assert tx.events["Harvested"]["profit"] > 0
    assert veangle_token.locked(strategy)[1] == int((chain.time() + strategy.timeToLock()) / WEEK) * WEEK

    # Go to end of new lock and withdraw manually
    chain.mine(1, timestamp=veangle_token.locked(strategy)[1] + 1)
    strategy.withdrawVeAngleManually({"from": gov})

    assert veangle_token.locked(strategy)[0] == 0
    assert veangle_token.locked(strategy)[1] == 0

    # Sell 90% of Angle now
    strategy.setSellInBips(9000, {"from":gov})
    tx = strategy.harvest({"from": strategist})