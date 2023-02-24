// Copyright © Aptos Foundation
// Parts of the project are originally copyright © Meta Platforms, Inc.
// SPDX-License-Identifier: Apache-2.0

pub mod cache;
pub mod view;

use crate::storage::{FileHandle, ShellSafeName, TextLine};
use anyhow::{ensure, Result};
use aptos_crypto::HashValue;
use aptos_types::transaction::Version;
use serde::{Deserialize, Serialize};
use std::convert::TryInto;

#[derive(Deserialize, Serialize)]
#[allow(clippy::enum_variant_names)] // to introduce: BackupperId, etc
pub(crate) enum Metadata {
    EpochEndingBackup(EpochEndingBackupMeta),
    EpochEndingBackupRange(EpochEndingBackupMetaRange),
    StateSnapshotBackup(StateSnapshotBackupMeta),
    StateSnapshotBackupRange(StateSnapshotBackupMetaRange),
    TransactionBackup(TransactionBackupMeta),
    TransactionBackupRange(TransactionBackupMetaRange),
    Identity(IdentityMeta),
}

impl Metadata {
    pub fn new_epoch_ending_backup(
        first_epoch: u64,
        last_epoch: u64,
        first_version: Version,
        last_version: Version,
        manifest: FileHandle,
    ) -> Self {
        Self::EpochEndingBackup(EpochEndingBackupMeta {
            first_epoch,
            last_epoch,
            first_version,
            last_version,
            manifest,
        })
    }

    pub fn new_state_snapshot_backup(epoch: u64, version: Version, manifest: FileHandle) -> Self {
        Self::StateSnapshotBackup(StateSnapshotBackupMeta {
            epoch,
            version,
            manifest,
        })
    }

    pub fn new_transaction_backup(
        first_version: Version,
        last_version: Version,
        manifest: FileHandle,
    ) -> Self {
        Self::TransactionBackup(TransactionBackupMeta {
            first_version,
            last_version,
            manifest,
        })
    }

    pub fn new_epoch_ending_backup_range(backup_metas: Vec<EpochEndingBackupMeta>) -> Result<Self> {
        ensure!(
            !backup_metas.is_empty(),
            "compacting an empty metadata vector"
        );
        let backup_meta = &backup_metas[0];
        let first_epoch = backup_meta.first_epoch;
        let mut next_epoch = backup_meta.last_epoch + 1; // non inclusive
        let first_version = backup_meta.first_version;
        let mut next_version = backup_meta.last_version;

        for backup in backup_metas.iter().skip(1) {
            ensure!(
                next_epoch == backup.first_epoch,
                "Epoch ending backup ranges is not continuous expecting epoch {}, got {}.",
                next_epoch,
                backup.first_epoch,
            );
            next_epoch = backup.last_epoch + 1;
            next_version = backup.last_version;
        }

        Ok(Self::EpochEndingBackupRange(EpochEndingBackupMetaRange {
            first_epoch,
            last_epoch: next_epoch - 1,
            first_version,
            last_version: next_version,
            backup_metas,
        }))
    }

    pub fn new_statesnapshot_backup_range(
        backup_metas: Vec<StateSnapshotBackupMeta>,
    ) -> Result<Self> {
        ensure!(
            !backup_metas.is_empty(),
            "compacting an empty metadata vector"
        );
        let backup_meta = &backup_metas[0];
        let first_epoch = backup_meta.epoch;
        let mut next_epoch = backup_meta.epoch + 1;
        let first_version = backup_meta.version;
        let mut next_version = backup_meta.version + 1;

        for backup in backup_metas.iter().skip(1) {
            ensure!(
                next_epoch == backup.epoch,
                "state backup ranges is not continuous expecting epoch {}, got {}.",
                next_epoch,
                backup.epoch,
            );
            next_epoch = backup.epoch + 1;
            ensure!(
                next_version == backup.version,
                "state backup ranges is not continuous expecting version {}, got {}.",
                next_version,
                backup.version,
            );
            next_version = backup.version + 1;
        }

        Ok(Self::StateSnapshotBackupRange(
            StateSnapshotBackupMetaRange {
                first_epoch,
                last_epoch: next_epoch - 1,
                first_version,
                last_version: next_version - 1,
                backup_metas,
            },
        ))
    }

    pub fn new_transaction_backup_range(backup_metas: Vec<TransactionBackupMeta>) -> Result<Self> {
        ensure!(
            !backup_metas.is_empty(),
            "compacting an empty metadata vector"
        );
        // assume the vector is sorted based on version
        let backup_meta = &backup_metas[0];
        let first_version = backup_meta.first_version;
        // assume the last_version is inclusive in the backup meta
        let mut next_version = backup_meta.last_version + 1;

        for backup in backup_metas.iter().skip(1) {
            ensure!(
                next_version == backup.first_version,
                "txn backup ranges is not continuous expecting version {}, got {}.",
                next_version,
                backup.first_version,
            );
            next_version = backup.last_version + 1;
        }

        Ok(Self::TransactionBackupRange(TransactionBackupMetaRange {
            first_version,
            last_version: next_version - 1,
            backup_metas,
        }))
    }

    pub fn new_random_identity() -> Self {
        Self::Identity(IdentityMeta {
            id: HashValue::random(),
        })
    }

    pub fn name(&self) -> ShellSafeName {
        match self {
            Self::EpochEndingBackup(e) => {
                format!("epoch_ending_{}-{}.meta", e.first_epoch, e.last_epoch)
            },
            Self::StateSnapshotBackup(s) => format!("state_snapshot_ver_{}.meta", s.version),
            Self::TransactionBackup(t) => {
                format!("transaction_{}-{}.meta", t.first_version, t.last_version,)
            },
            Self::EpochEndingBackupRange(e) => {
                format!(
                    "epoch_ending_compacted_{}-{}.meta",
                    e.first_epoch, e.last_epoch
                )
            },
            Self::StateSnapshotBackupRange(e) => {
                format!(
                    "state_snapshot_compacted_ver_{}-{}.meta",
                    e.first_version, e.last_version
                )
            },
            Self::TransactionBackupRange(e) => {
                format!(
                    "transaction_compacted_{}-{}.meta",
                    e.first_version, e.last_version
                )
            },
            Metadata::Identity(_) => "identity.meta".into(),
        }
        .try_into()
        .unwrap()
    }

    pub fn to_text_line(&self) -> Result<TextLine> {
        TextLine::new(&serde_json::to_string(self)?)
    }
}

#[derive(Clone, Deserialize, Serialize, Eq, PartialEq, Ord, PartialOrd)]
pub struct EpochEndingBackupMetaRange {
    pub first_epoch: u64,
    pub last_epoch: u64,
    pub first_version: Version,
    pub last_version: Version,
    pub backup_metas: Vec<EpochEndingBackupMeta>,
}

#[derive(Clone, Debug, Deserialize, Serialize, Eq, PartialEq, Ord, PartialOrd)]
pub struct EpochEndingBackupMeta {
    pub first_epoch: u64,
    pub last_epoch: u64,
    pub first_version: Version,
    pub last_version: Version,
    pub manifest: FileHandle,
}

#[derive(Clone, Deserialize, Serialize, Eq, PartialEq, Ord, PartialOrd)]
pub struct StateSnapshotBackupMetaRange {
    pub first_epoch: u64,
    pub last_epoch: u64,
    pub first_version: Version,
    pub last_version: Version,
    pub backup_metas: Vec<StateSnapshotBackupMeta>,
}

#[derive(Clone, Debug, Deserialize, Serialize, Eq, PartialEq, Ord, PartialOrd)]
pub struct StateSnapshotBackupMeta {
    pub epoch: u64,
    pub version: Version,
    pub manifest: FileHandle,
}

#[derive(Clone, Deserialize, Serialize, Eq, PartialEq, Ord, PartialOrd)]
pub struct TransactionBackupMetaRange {
    pub first_version: Version,
    pub last_version: Version,
    pub backup_metas: Vec<TransactionBackupMeta>,
}

#[derive(Clone, Debug, Deserialize, Serialize, Eq, PartialEq, Ord, PartialOrd)]
pub struct TransactionBackupMeta {
    pub first_version: Version,
    pub last_version: Version,
    pub manifest: FileHandle,
}

#[derive(Clone, Debug, Deserialize, Serialize, Eq, PartialEq, Ord, PartialOrd)]
pub struct IdentityMeta {
    pub id: HashValue,
}
