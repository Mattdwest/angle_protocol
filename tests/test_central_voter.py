import pytest
from brownie import Contract

@pytest.mark.require_network("mainnet-fork")
def test_central_voter(
    chain,
    vault,
    strategy,
    token,
    gov,
    strategist,
    live_yearn_treasury,
    alice,
    alice_amount,
    bob,
    bob_amount,
    tinytim,
    tinytim_amount,
    angle_token,
    veangle_token,
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
    previous_voter_angle = angle_token.balanceOf(angle_voter)
    previous_proxy_angle = angle_token.balanceOf(strategy_proxy)

    strategy.harvest({"from": strategist})

    assert angle_token.balanceOf(angle_voter) == previous_voter_angle
    assert angle_token.balanceOf(strategy_proxy) - previous_proxy_angle > 0

    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one > assets_at_t

    whitelister = Contract(veangle_token.smart_wallet_checker())
    whitelister.approveWallet(angle_voter, {"from": whitelister.admin()})

    angle_balance = angle_token.balanceOf(strategy_proxy)
    lock_now = int(angle_balance / 2)

    unlock_time = chain.time() + 4*86400*365
    strategy_proxy.lock(lock_now, unlock_time, {"from": gov})

    assert veangle_token.balanceOf(angle_voter) > 0
    assert veangle_token.locked(angle_voter)[0] == lock_now
    assert veangle_token.locked(angle_voter)[1] - chain.time() > 4*86400*364

    lock_rest = angle_balance - lock_now
    strategy_proxy.increaseAmount(lock_rest, {"from": gov})
    assert veangle_token.locked(angle_voter)[0] == angle_balance

    utils.mock_angle_slp_profits()

    strategy.harvest({"from": strategist})
    