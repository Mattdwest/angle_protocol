import pytest
from brownie import ZERO_ADDRESS


@pytest.mark.require_network("mainnet-fork")
def test_angle_hack(
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
    accounts,
    deploy_strategy_proxy,
    deploy_angle_voter
):
    token.approve(vault, 1_000_000_000_000, {"from": alice})

    vault.deposit(alice_amount, {"from": alice})

    assert san_token.balanceOf(strategy) == 0

    utils.set_0_vault_fees()

    # First harvest
    chain.sleep(1)
    strategy.harvest({"from": strategist})

    assert san_token_gauge.balanceOf(deploy_angle_voter) > 0
    assets_at_t = strategy.estimatedTotalAssets()

    chain.sleep(10 ** 10)
    chain.mine(100)

    before_harvest_treasury_rewards_bal = angle_token.balanceOf(live_yearn_treasury)
    strategy.harvest({"from": strategist})
    after_harvest_treasury_rewards_bal = angle_token.balanceOf(live_yearn_treasury)
    assert after_harvest_treasury_rewards_bal > before_harvest_treasury_rewards_bal

    chain.sleep(3600 * 24 * 2)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)

    # Here's the hack part, where we fake a hack by sending away all of the strat's gauge tokens
    san_token_gauge.transfer(
        ZERO_ADDRESS, san_token_gauge.balanceOf(deploy_angle_voter), {"from": deploy_angle_voter}
    )

    strategy.setDoHealthCheck(False, {"from": gov})
    strategy.harvest({"from": strategist})
    assets_at_t_plus_one = strategy.estimatedTotalAssets()
    assert assets_at_t_plus_one < assets_at_t

    vault.withdraw({"from": alice})

    assert token.balanceOf(alice) < alice_amount
