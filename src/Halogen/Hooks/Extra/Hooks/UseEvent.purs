module Example.Hooks.Extra.Hooks.UseEvent
  ( useEvent
  , subscribeTo
  , subscribeTo'
  , UseEvent
  , EventEqFn
  , EventProps
  , CapturesWith_TypeSignature
  , UseTickEffect_TypeSignature
  , EventApi
  )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype)
import Data.Traversable (for_)
import Data.Tuple.Nested ((/\))
import Halogen.Hooks (HookM, Hooked, MemoValues, UseEffect, UseState, Hook, useState)
import Halogen.Hooks as Hooks

newtype UseEvent a hooks = UseEvent (UseState (Maybe a) hooks)

derive instance newtypeUseEvent :: Newtype (UseEvent a hooks) _

type UseTickEffect_TypeSignature slots output m =
  HookM slots output m (Maybe (HookM slots output m Unit))
  -> (forall hooks. Hooked slots output m hooks (UseEffect hooks) Unit)

type CapturesWith_TypeSignature slots output m a =
  EventEqFn a
    -> (MemoValues -> UseTickEffect_TypeSignature slots output m)
    -> UseTickEffect_TypeSignature slots output m

type EventEqFn a =
  { state :: Maybe a } -> { state :: Maybe a } -> Boolean

type EventProps slots output m a =
  { capturesWith :: CapturesWith_TypeSignature slots output m a
  , subscribe :: (a -> HookM slots output m Unit) -> HookM slots output m Unit
  }

type EventApi slots output m a =
  { push :: a -> HookM slots output m Unit
  , props :: EventProps slots output m a
  }

-- | Allows you to "push" events that occur inside a hook
-- | to outside of the hook, so that some end-user
-- | can 1) handle those events when they occur while 2) having
-- | full access to the API exposed to the hook in its returned value:
-- | ```
-- | -- in your custom Hook code...
-- | onSomeEvent <- useEvent
-- |
-- | -- somewhere in your HookM code
-- |   onSomeEvent.push "user clicked foo"
-- |
-- | Hooks.pure
-- |   { onSomeEvent: onSomeEvent.props }
-- |
-- | --------------
-- | -- in end-user code
-- |
-- | someLib <- useSomeLibHook
-- | subscribeTo someLib.onSomeEvent \string -> do
-- |   Hooks.raise ("Event occurred: " <> string)
-- | ```
useEvent
  :: forall output m slots a
   . Hook slots output m (UseEvent a) (EventApi slots output m a)
useEvent = Hooks.wrap Hooks.do
  state /\ tState <- useState Nothing

  Hooks.pure { push: \value -> Hooks.put tState (Just value)
             , props: { capturesWith: \eqFn -> Hooks.capturesWith eqFn { state }
                      , subscribe: \cb -> do
                          state' <- Hooks.get tState
                          for_ state' cb
                          Hooks.put tState Nothing
                      }
             }

-- | Long story short, it cleans up what you would otherwise write when
-- | subscribing to events that a hook emits.
-- | Via this function, you would write this...
-- | ```
-- | someLib <- useSomLibHook
-- | subscribeTo someLib.onSomeEvent \string -> do
-- |   Hooks.put stateToken ("Event occurred: " <> string)
-- | ```
-- | ... instead of this ...
-- | ```
-- | someLib <- useSomLibHook
-- | someLib.onSomeEvent.capturesWith (==) Hooks.useTickEffect do
-- |   someLib.onSomeEvent.subscribe \string -> do
-- |      Hooks.put stateToken ("Event occurred: " <> string)
-- |   pure Nothing
-- | ```
subscribeTo
  :: forall slots output m a
   . Eq a
  => EventProps slots output m a
  -> (a -> HookM slots output m Unit)
  -> Hook slots output m UseEffect Unit
subscribeTo props cb =
  subscribeTo' props (==) cb

-- | Long story short, it cleans up what you would otherwise write when
-- | subscribing to events that a hook emits.
-- | Via this function, you would write this...
-- | ```
-- | someLib <- useSomLibHook
-- | let eqFn = \l r => l.someValue == r.someValue
-- | subscribeTo' someLib.onSomeEvent eqFn \string -> do
-- |   Hooks.put stateToken ("Event occurred: " <> string)
-- | ```
-- | ... instead of this ...
-- | ```
-- | someLib <- useSomLibHook
-- | let eqFn = \l r => l.someValue == r.someValue
-- | someLib.onSomeEvent.capturesWith eqFn Hooks.useTickEffect do
-- |   someLib.onSomeEvent.subscribe \string -> do
-- |      Hooks.put stateToken ("Event occurred: " <> string)
-- |   pure Nothing
-- | ```
subscribeTo'
  :: forall a m output slots
   . EventProps slots output m a
  -> EventEqFn a
  -> (a -> HookM slots output m Unit)
  -> Hook slots output m UseEffect Unit
subscribeTo' props eqFn cb =
  props.capturesWith eqFn Hooks.useTickEffect do
    props.subscribe cb
    pure Nothing