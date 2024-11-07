-include .env 

.PHONEY: all test deploy

build :; forge build

test :; forge test

# if commands are bigger, we can do:
# test:
# 	forge test	

install :; forge install cyfrin/foundry-devops@0.2.2 --no-commit && forge install smartcontractkit/chainlink-bronie-contracts@1.1.1 --no-commit && forge install foundry-rs/forge-std@v1.8.2 --no-commit && forge install transmissions11/solmate@v6 --no-commit

deploy-anvil:
	@
	
deploy-sepolia: # @ obfuscates the command and it does not show up on the terminal
	@forge script script/DeployRaffle.s.sol:DeployRaffle --rpc-url $(SEPOLIA_RPC_URL) --account Dev1 --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

