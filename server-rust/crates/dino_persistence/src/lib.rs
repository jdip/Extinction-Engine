use dino_sim::WorldState;

pub const SAVE_VERSION: u16 = 1;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SaveMetadata {
    pub save_version: u16,
    pub world_seed: u64,
    pub world_tick: u64,
    pub state_hash: u64,
}

impl SaveMetadata {
    pub const fn new(world_seed: u64, world_tick: u64, state_hash: u64) -> Self {
        Self {
            save_version: SAVE_VERSION,
            world_seed,
            world_tick,
            state_hash,
        }
    }
}

pub fn metadata_from_world(world: &WorldState) -> SaveMetadata {
    SaveMetadata::new(world.seed(), world.time().tick(), world.state_hash())
}

#[cfg(test)]
mod tests {
    use super::*;
    use dino_sim::{tick_world, PlayerCommand, PrototypeId, WorldConfig, WorldState};

    #[test]
    fn metadata_preserves_save_version_seed_tick_and_hash() {
        let mut world = WorldState::new(WorldConfig::new(12));
        tick_world(
            &mut world,
            &[PlayerCommand::BuildPrototype {
                prototype: PrototypeId::new(4),
            }],
        );

        let metadata = metadata_from_world(&world);

        assert_eq!(metadata.save_version, SAVE_VERSION);
        assert_eq!(metadata.world_seed, 12);
        assert_eq!(metadata.world_tick, 1);
        assert_eq!(metadata.state_hash, world.state_hash());
    }
}
