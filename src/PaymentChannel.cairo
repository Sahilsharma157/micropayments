#[starknet::contract]
mod PaymentChannel {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess,
        StorageMapReadAccess, StorageMapWriteAccess, Map
    };

    #[storage]
    struct Storage {
        owner: ContractAddress,
        total_settlements: u128,
        settlement_hashes: Map<u128, felt252>,
        settlement_timestamps: Map<u128, u64>,
        settlement_count: Map<u128, u32>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SettlementAdded: SettlementAdded,
    }

    #[derive(Drop, starknet::Event)]
    struct SettlementAdded {
        #[key]
        settlement_id: u128,
        batch_hash: felt252,
        timestamp: u64,
        payment_count: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.total_settlements.write(0);
    }

    #[abi(embed_v0)]
    impl PaymentChannelImpl of super::IPaymentChannel<ContractState> {
        fn add_settlement(
            ref self: ContractState,
            batch_hash: felt252,
            timestamp: u64,
            payment_count: u32
        ) {
            let _caller = get_caller_address();
            
            // Generate new settlement ID
            let settlement_id = self.total_settlements.read() + 1;
            self.total_settlements.write(settlement_id);

            // Store settlement data
            self.settlement_hashes.write(settlement_id, batch_hash);
            self.settlement_timestamps.write(settlement_id, timestamp);
            self.settlement_count.write(settlement_id, payment_count);

            // Emit event
            self.emit(SettlementAdded {
                settlement_id,
                batch_hash,
                timestamp,
                payment_count,
            });
        }

        fn get_settlement(self: @ContractState, settlement_id: u128) -> (felt252, u64, u32) {
            let hash = self.settlement_hashes.read(settlement_id);
            let timestamp = self.settlement_timestamps.read(settlement_id);
            let count = self.settlement_count.read(settlement_id);
            (hash, timestamp, count)
        }

        fn get_total(self: @ContractState) -> u128 {
            self.total_settlements.read()
        }
    }
}

#[starknet::interface]
trait IPaymentChannel<TContractState> {
    fn add_settlement(
        ref self: TContractState,
        batch_hash: felt252,
        timestamp: u64,
        payment_count: u32
    );
    fn get_settlement(self: @TContractState, settlement_id: u128) -> (felt252, u64, u32);
    fn get_total(self: @TContractState) -> u128;
}
