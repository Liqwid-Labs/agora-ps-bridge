{- |
Module     : Sample.Stake
Maintainer : emi@haskell.fyi
Description: Sample based testing for Stake utxos

This module tests primarily the happy path for Stake creation
-}
module Sample.Stake (
  stake,
  stakeAssetClass,
  stakeSymbol,
  validatorHashTN,
  signer,

  -- * Script contexts
  stakeCreation,
  stakeCreationWrongDatum,
  stakeCreationUnsigned,
  stakeDepositWithdraw,
  DepositWithdrawExample (..),
) where

import Agora.SafeMoney (GTTag)
import Agora.Stake (
  Stake (gtClassRef),
  StakeDatum (StakeDatum, stakedAmount),
 )
import Agora.Stake.Scripts (stakeValidator)
import Data.Tagged (Tagged, untag)
import Plutarch.Api.V1 (mkValidator, validatorHash)
import Plutarch.Context (
  MintingBuilder,
  SpendingBuilder,
  buildMintingUnsafe,
  buildSpendingUnsafe,
  input,
  mint,
  output,
  script,
  signedWith,
  txId,
  withDatum,
  withSpending,
  withTxId,
  withValue,
 )
import PlutusLedgerApi.V1 (
  Datum (Datum),
  ScriptContext (..),
  ScriptPurpose (Minting),
  ToData (toBuiltinData),
  TokenName (TokenName),
  TxInfo (txInfoData, txInfoSignatories),
  ValidatorHash (ValidatorHash),
 )
import PlutusLedgerApi.V1.Value qualified as Value (
  assetClassValue,
  singleton,
 )
import Sample.Shared (
  signer,
  stake,
  stakeAssetClass,
  stakeSymbol,
  stakeValidatorHash,
 )

-- | 'TokenName' that represents the hash of the 'Stake' validator.
validatorHashTN :: TokenName
validatorHashTN = let ValidatorHash vh = validatorHash (mkValidator $ stakeValidator stake) in TokenName vh

-- | This script context should be a valid transaction.
stakeCreation :: ScriptContext
stakeCreation =
  let st = Value.assetClassValue stakeAssetClass 1 -- Stake ST
      datum :: StakeDatum
      datum = StakeDatum 424242424242 signer []

      builder :: MintingBuilder
      builder =
        mconcat
          [ txId "0b2086cbf8b6900f8cb65e012de4516cb66b5cb08a9aaba12a8b88be"
          , signedWith signer
          , mint st
          , output $
              script stakeValidatorHash
                . withValue (st <> Value.singleton "da8c30857834c6ae7203935b89278c532b3995245295456f993e1d24" "LQ" 424242424242)
                . withDatum datum
          ]
   in buildMintingUnsafe builder

-- | This ScriptContext should fail because the datum has too much GT.
stakeCreationWrongDatum :: ScriptContext
stakeCreationWrongDatum =
  let datum :: Datum
      datum = Datum (toBuiltinData $ StakeDatum 4242424242424242 signer []) -- Too much GT
   in ScriptContext
        { scriptContextTxInfo = stakeCreation.scriptContextTxInfo {txInfoData = [("", datum)]}
        , scriptContextPurpose = Minting stakeSymbol
        }

-- | This ScriptContext should fail because the datum has too much GT.
stakeCreationUnsigned :: ScriptContext
stakeCreationUnsigned =
  ScriptContext
    { scriptContextTxInfo =
        stakeCreation.scriptContextTxInfo
          { txInfoSignatories = []
          }
    , scriptContextPurpose = Minting stakeSymbol
    }

--------------------------------------------------------------------------------

-- | Config for creating a ScriptContext that deposits or withdraws.
data DepositWithdrawExample = DepositWithdrawExample
  { startAmount :: Tagged GTTag Integer
  -- ^ The amount of GT stored before the transaction.
  , delta :: Tagged GTTag Integer
  -- ^ The amount of GT deposited or withdrawn from the Stake.
  }

-- | Create a ScriptContext that deposits or withdraws, given the config for it.
stakeDepositWithdraw :: DepositWithdrawExample -> ScriptContext
stakeDepositWithdraw config =
  let st = Value.assetClassValue stakeAssetClass 1 -- Stake ST
      stakeBefore :: StakeDatum
      stakeBefore = StakeDatum config.startAmount signer []

      stakeAfter :: StakeDatum
      stakeAfter = stakeBefore {stakedAmount = stakeBefore.stakedAmount + config.delta}

      builder :: SpendingBuilder
      builder =
        mconcat
          [ txId "0b2086cbf8b6900f8cb65e012de4516cb66b5cb08a9aaba12a8b88be"
          , signedWith signer
          , mint st
          , input $
              script stakeValidatorHash
                . withValue (st <> Value.assetClassValue (untag stake.gtClassRef) (untag stakeBefore.stakedAmount))
                . withDatum stakeAfter
                . withTxId "0b2086cbf8b6900f8cb65e012de4516cb66b5cb08a9aaba12a8b88be"
          , output $
              script stakeValidatorHash
                . withValue (st <> Value.assetClassValue (untag stake.gtClassRef) (untag stakeAfter.stakedAmount))
                . withDatum stakeAfter
          , withSpending $
              script stakeValidatorHash
                . withValue (st <> Value.assetClassValue (untag stake.gtClassRef) (untag stakeBefore.stakedAmount))
                . withDatum stakeAfter
          ]
   in buildSpendingUnsafe builder
