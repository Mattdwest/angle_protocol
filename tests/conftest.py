import pytest
from brownie import config, Contract

# # Snapshots the chain before each test and reverts after test completion.
@pytest.fixture(autouse=True)
def shared_setup(fn_isolation):
    pass


@pytest.fixture(scope="module", autouse=True)
def gov(accounts):
    yield accounts[0]


@pytest.fixture(scope="module", autouse=True)
def rewards(accounts):
    yield accounts[1]


@pytest.fixture(scope="module", autouse=True)
def guardian(accounts):
    yield accounts[2]


@pytest.fixture(scope="module", autouse=True)
def management(accounts):
    yield accounts[3]


@pytest.fixture(scope="module", autouse=True)
def strategist(accounts):
    yield accounts[4]


@pytest.fixture(scope="module", autouse=True)
def keeper(accounts):
    yield accounts[5]


@pytest.fixture(scope="module", autouse=True)
def alice(accounts):
    yield accounts[6]


@pytest.fixture(scope="module", autouse=True)
def bob(accounts):
    yield accounts[7]


@pytest.fixture(scope="module", autouse=True)
def tinytim(accounts):
    yield accounts[8]


@pytest.fixture(scope="module", autouse=True)
def token_whale(accounts):
    whale_address = "0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7"  # Curve pool
    yield accounts.at(whale_address, force=True)


@pytest.fixture(scope="module", autouse=True)
def token():
    token_address = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
    yield Contract(token_address)


@pytest.fixture(scope="module", autouse=True)
def alice_amount(alice, token, token_whale):
    amount = 4_000_000_000
    token.transfer(alice, amount, {"from": token_whale})
    yield amount


@pytest.fixture(scope="module", autouse=True)
def bob_amount(bob, token, token_whale):
    amount = 1_000_000_000
    token.transfer(bob, amount, {"from": token_whale})
    yield amount


@pytest.fixture(scope="module", autouse=True)
def tinytim_amount(tinytim, token, token_whale):
    amount = 10_000_000
    token.transfer(tinytim, amount, {"from": token_whale})
    yield amount


@pytest.fixture(scope="module", autouse=True)
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, {"from": gov})
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture(scope="module", autouse=True)
def strategy(
    strategist,
    guardian,
    keeper,
    vault,
    StrategyAngleUSDC,
    gov,
    san_token,
    angle_token,
    uni,
    angle_stable_master,
    san_token_gauge,
    pool_manager,
):
    strategy = strategist.deploy(
        StrategyAngleUSDC,
        vault,
        san_token,
        angle_token,
        uni,
        angle_stable_master,
        san_token_gauge,
        pool_manager,
    )
    strategy.setKeeper(keeper, {"from": gov})
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


# sushiswap router
@pytest.fixture(scope="module", autouse=True)
def uni():
    yield Contract("0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F")


# USDC san_token
@pytest.fixture(scope="module", autouse=True)
def san_token():
    yield Contract.from_explorer("0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad")


# USDC san_token whale
@pytest.fixture(scope="module", autouse=True)
def san_token_whale(accounts):
    address = "0x51fE22abAF4a26631b2913E417c0560D547797a7"  # USDC san_token guage
    yield accounts.at(address, force=True)


@pytest.fixture(scope="module", autouse=True)
def angle_token():
    yield Contract("0x31429d1856aD1377A8A0079410B297e1a9e214c2")


@pytest.fixture(scope="module", autouse=True)
def angle_token_whale(accounts):
    yield accounts.at("0xe02F8E39b8cFA7d3b62307E46077669010883459", force=True)


@pytest.fixture(scope="module", autouse=True)
def veangle_token():
    yield Contract("0x0C462Dbb9EC8cD1630f1728B2CFD2769d09f0dd5")


# stable manager front
@pytest.fixture(scope="module", autouse=True)
def angle_stable_master():
    yield Contract("0x5adDc89785D75C86aB939E9e15bfBBb7Fc086A87")


# usdc stake
@pytest.fixture(scope="module", autouse=True)
def san_token_gauge():
    yield Contract("0x51fE22abAF4a26631b2913E417c0560D547797a7")


@pytest.fixture(scope="module", autouse=True)
def pool_manager():
    yield Contract("0xe9f183FC656656f1F17af1F2b0dF79b8fF9ad8eD")


@pytest.fixture(scope="module", autouse=True)
def live_yearn_treasury():
    address = "0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde"
    yield Contract(address)


@pytest.fixture(scope="module", autouse=True)
def newstrategy(
    strategist,
    guardian,
    keeper,
    vault,
    StrategyAngleUSDC,
    gov,
    san_token,
    angle_token,
    uni,
    angle_stable_master,
    san_token_gauge,
    pool_manager,
):
    newstrategy = guardian.deploy(
        StrategyAngleUSDC,
        vault,
        san_token,
        angle_token,
        uni,
        angle_stable_master,
        san_token_gauge,
        pool_manager,
    )
    newstrategy.setKeeper(keeper)
    yield newstrategy


@pytest.fixture(scope="module", autouse=True)
def fxs_liquidity(accounts):
    yield accounts.at("0xf977814e90da44bfa03b6295a0616a897441acec", force=True)


@pytest.fixture(scope="module", autouse=True)
def token_owner(accounts):
    yield accounts.at("0x8412ebf45bac1b340bbe8f318b928c466c4e39ca", force=True)


@pytest.fixture(scope="module", autouse=True)
def angle_gov(accounts):
    address = "0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8"
    yield accounts.at(address, force=True)


@pytest.fixture(scope="module", autouse=True)
def angle_fee_manager(accounts):
    address = "0x97B6897AAd7aBa3861c04C0e6388Fc02AF1F227f"
    yield accounts.at(address, force=True)


@pytest.fixture(scope="module", autouse=True)
def pool_manager_account(accounts):
    address = "0xe9f183FC656656f1F17af1F2b0dF79b8fF9ad8eD"
    yield accounts.at(address, force=True)


@pytest.fixture(scope="session")
def BASE_PARAMS():
    yield 1000000000


@pytest.fixture(scope="module", autouse=True)
def utils(
    chain,
    pool_manager_account,
    pool_manager,
    angle_stable_master,
    strategy,
    vault,
    gov,
    token,
    san_token_gauge,
    san_token,
):
    return Utils(
        chain,
        pool_manager_account,
        pool_manager,
        angle_stable_master,
        strategy,
        vault,
        gov,
        token,
        san_token_gauge,
        san_token,
    )


class Utils:
    def __init__(
        self,
        chain,
        pool_manager_account,
        pool_manager,
        angle_stable_master,
        strategy,
        vault,
        gov,
        token,
        san_token_gauge,
        san_token,
    ):
        self.chain = chain
        self.pool_manager_account = pool_manager_account
        self.pool_manager = pool_manager
        self.angle_stable_master = angle_stable_master
        self.strategy = strategy
        self.vault = vault
        self.gov = gov
        self.token = token
        self.san_token_gauge = san_token_gauge
        self.san_token = san_token

    def mock_angle_slp_profits(self):
        max_profits_per_block = self.angle_stable_master.collateralMap(
            self.pool_manager
        )[7][2]
        i = 0
        while i < 100:
            self.angle_stable_master.accumulateInterest(
                max_profits_per_block, {"from": self.pool_manager_account}
            )
            self.chain.mine(1)
            self.chain.sleep(1)
            i += 1

    def set_0_vault_fees(self):
        self.vault.setManagementFee(0, {"from": self.gov})
        self.vault.setPerformanceFee(0, {"from": self.gov})

    def assert_strategy_contains_no_tokens(self):
        assert self.token.balanceOf(self.strategy) == 0
        assert self.san_token_gauge.balanceOf(self.strategy) == 0
        assert self.san_token.balanceOf(self.strategy) == 0
