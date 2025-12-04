use starknet::ContractAddress;

#[starknet::interface]
trait IERC20<TContractState> {
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, 
        sender: ContractAddress, 
        recipient: ContractAddress, 
        amount: u256
    ) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

#[starknet::interface]
trait IPaymentChannelSettlement<TContractState> {
    fn settle_batch(
        ref self: TContractState,
        recipients: Array<ContractAddress>,
        amounts: Array<u256>,
        token_address: ContractAddress,
    ) -> felt252;
    fn get_settlement_count(self: @TContractState) -> u32;
    fn get_owner(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
mod PaymentChannelSettlement {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess, Map
    };
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        settlement_count: u32,
        settlement_hashes: Map<felt252, felt252>,
        settlement_timestamps: Map<felt252, u64>,
        settlement_payment_counts: Map<felt252, u32>,
        settlement_amounts: Map<felt252, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        BatchSettled: BatchSettled,
    }

    #[derive(Drop, starknet::Event)]
    struct BatchSettled {
        batch_hash: felt252,
        settler: ContractAddress,
        payment_count: u32,
        total_amount: u256,
        timestamp: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.settlement_count.write(0);
    }

    #[abi(embed_v0)]
    impl PaymentChannelSettlementImpl of super::IPaymentChannelSettlement<ContractState> {
        fn settle_batch(
            ref self: ContractState,
            recipients: Array<ContractAddress>,
            amounts: Array<u256>,
            token_address: ContractAddress,
        ) -> felt252 {
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            let payment_count = recipients.len();
            
            assert(payment_count == amounts.len(), 'Recipients and amounts mismatch');
            assert(payment_count > 0, 'No payments to settle');

            let token = IERC20Dispatcher { contract_address: token_address };
            
            let mut total: u256 = 0;
            let mut i: u32 = 0;
            
            loop {
                if i >= payment_count {
                    break;
                }
                
                let recipient = *recipients.at(i);
                let amount = *amounts.at(i);
                
                token.transfer_from(caller, recipient, amount);
                
                total += amount;
                i += 1;
            };

            let batch_hash: felt252 = (timestamp + payment_count.into()).into();
            
            self.settlement_hashes.write(batch_hash, batch_hash);
            self.settlement_timestamps.write(batch_hash, timestamp);
            self.settlement_payment_counts.write(batch_hash, payment_count);
            self.settlement_amounts.write(batch_hash, total);
            
            let current_count = self.settlement_count.read();
            self.settlement_count.write(current_count + 1);

            self.emit(Event::BatchSettled(
                BatchSettled {
                    batch_hash,
                    settler: caller,
                    payment_count,
                    total_amount: total,
                    timestamp,
                }
            ));
            
            batch_hash
        }

        fn get_settlement_count(self: @ContractState) -> u32 {
            self.settlement_count.read()
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}