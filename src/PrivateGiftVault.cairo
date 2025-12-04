#[starknet::contract]
mod PrivateGiftVault {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};

    #[storage]
    struct Storage {
        owner: ContractAddress,
        session_counter: u64,
        session_amounts: LegacyMap<u64, u256>,
        session_code_counts: LegacyMap<u64, u32>,
        session_organizers: LegacyMap<u64, ContractAddress>,
        commitments: LegacyMap<felt252, bool>,
        redeemed: LegacyMap<felt252, bool>,
        commitment_sessions: LegacyMap<felt252, u64>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GiftDropCreated: GiftDropCreated,
        CommitmentsBatched: CommitmentsBatched,
        GiftRedeemed: GiftRedeemed,
    }

    #[derive(Drop, starknet::Event)]
    struct GiftDropCreated {
        #[key]
        session_id: u64,
        total_amount: u256,
        code_count: u32,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct CommitmentsBatched {
        #[key]
        session_id: u64,
        commitment_count: u32,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct GiftRedeemed {
        #[key]
        commitment_hash: felt252,
        recipient: ContractAddress,
        amount: u256,
        timestamp: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.session_counter.write(1);
    }

    #[abi(embed_v0)]
    impl PrivateGiftVaultImpl of super::IPrivateGiftVault<ContractState> {
        fn create_gift_drop(ref self: ContractState, code_count: u32) -> u64 {
            assert(code_count > 0 && code_count <= 100, 'Invalid code count');
            
            let caller = get_caller_address();
            let session_id = self.session_counter.read();
            
            self.session_code_counts.write(session_id, code_count);
            self.session_organizers.write(session_id, caller);
            self.session_counter.write(session_id + 1);
            
            self.emit(GiftDropCreated {
                session_id,
                total_amount: 0,
                code_count,
                timestamp: get_block_timestamp(),
            });
            
            session_id
        }

        fn batch_commitments(
            ref self: ContractState,
            session_id: u64,
            commitment_hashes: Span<felt252>,
            total_amount: u256
        ) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            
            assert(caller == owner, 'Unauthorized');
            
            let mut i: u32 = 0;
            loop {
                if i >= commitment_hashes.len() {
                    break;
                }
                let hash = *commitment_hashes.at(i);
                self.commitments.write(hash, true);
                self.commitment_sessions.write(hash, session_id);
                i += 1;
            };
            
            self.session_amounts.write(session_id, total_amount);
            
            self.emit(CommitmentsBatched {
                session_id,
                commitment_count: commitment_hashes.len(),
                timestamp: get_block_timestamp(),
            });
        }

        fn redeem_gift(
            ref self: ContractState,
            commitment_hash: felt252,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(self.commitments.read(commitment_hash), 'Invalid commitment');
            assert(!self.redeemed.read(commitment_hash), 'Already redeemed');
            
            self.redeemed.write(commitment_hash, true);
            
            self.emit(GiftRedeemed {
                commitment_hash,
                recipient,
                amount,
                timestamp: get_block_timestamp(),
            });
        }

        fn verify_commitment(self: @ContractState, commitment_hash: felt252) -> bool {
            self.commitments.read(commitment_hash)
        }

        fn is_redeemed(self: @ContractState, commitment_hash: felt252) -> bool {
            self.redeemed.read(commitment_hash)
        }

        fn get_session_amount(self: @ContractState, session_id: u64) -> u256 {
            self.session_amounts.read(session_id)
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}

#[starknet::interface]
trait IPrivateGiftVault<TContractState> {
    fn create_gift_drop(ref self: TContractState, code_count: u32) -> u64;
    fn batch_commitments(
        ref self: TContractState,
        session_id: u64,
        commitment_hashes: Span<felt252>,
        total_amount: u256
    );
    fn redeem_gift(
        ref self: TContractState,
        commitment_hash: felt252,
        recipient: ContractAddress,
        amount: u256
    );
    fn verify_commitment(self: @TContractState, commitment_hash: felt252) -> bool;
    fn is_redeemed(self: @TContractState, commitment_hash: felt252) -> bool;
    fn get_session_amount(self: @TContractState, session_id: u64) -> u256;
    fn get_owner(self: @TContractState) -> ContractAddress;
}
