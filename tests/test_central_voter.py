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
    deploy_strategy_proxy,
    deploy_angle_voter
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
    assert san_token_gauge.balanceOf(deploy_strategy_proxy) == 0
    assert san_token_gauge.balanceOf(deploy_angle_voter) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    utils.mock_angle_slp_profits()
    previous_voter_angle = angle_token.balanceOf(deploy_angle_voter)
    previous_proxy_angle = angle_token.balanceOf(deploy_strategy_proxy)
    previous_treasury_angle = angle_token.balanceOf(live_yearn_treasury)

    strategy.harvest({"from": strategist})

    assert angle_token.balanceOf(deploy_angle_voter) == previous_voter_angle
    assert angle_token.balanceOf(deploy_strategy_proxy) - previous_proxy_angle > 0
    assert angle_token.balanceOf(live_yearn_treasury) - previous_treasury_angle > 0

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

    whitelister = Contract(veangle_token.smart_wallet_checker())
    whitelister.approveWallet(deploy_angle_voter, {"from": whitelister.admin()})

    angle_balance = angle_token.balanceOf(deploy_strategy_proxy)
    lock_now = int(angle_balance / 2)

    unlock_time = chain.time() + 4*86400*365
    deploy_strategy_proxy.lock(lock_now, unlock_time, {"from": gov})

    assert veangle_token.balanceOf(deploy_angle_voter) > 0
    assert veangle_token.locked(deploy_angle_voter)[0] == lock_now
    assert veangle_token.locked(deploy_angle_voter)[1] - chain.time() > 4*86400*364

    lock_rest = angle_balance - lock_now
    deploy_strategy_proxy.increaseAmount(lock_rest, {"from": gov})
    assert veangle_token.locked(deploy_angle_voter)[0] == angle_balance