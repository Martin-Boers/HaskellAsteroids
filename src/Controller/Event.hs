module Controller.Event (
    eventHandler
) where

import Control.Lens
import Graphics.Gloss
import Graphics.Gloss.Interface.Pure.Game

import Model

-- | Event handling


--Returns a world with the rotateAction/movementAction changed to needed value
eventHandler :: Event -> World -> World
eventHandler (EventKey (SpecialKey KeyLeft ) Down _ _)
    = rotateAction .~ RotateLeft
eventHandler (EventKey (SpecialKey KeyLeft ) Up   _ _)
    = rotateAction .~ NoRotation
eventHandler (EventKey (SpecialKey KeyRight) Down _ _)
    = rotateAction .~ RotateRight
eventHandler (EventKey (SpecialKey KeyRight) Up   _ _)
    = rotateAction .~ NoRotation
eventHandler (EventKey (SpecialKey KeyUp   ) Down _ _)
    =   (movementAction .~ Thrust)
      . (doesSelectPrev .~ True)
eventHandler (EventKey (SpecialKey KeyUp   ) Up   _ _)
    = movementAction .~ NoMovement
eventHandler (EventKey (SpecialKey KeyDown ) Down _ _)
    = doesSelectNext .~ True
eventHandler (EventKey (SpecialKey KeySpace) Down _ _)
    =   (shootAction .~ Shoot)
      . (doesConfirm .~ True)
eventHandler (EventKey (SpecialKey KeySpace) Up   _ _)
    = shootAction .~ DontShoot
eventHandler (EventKey (SpecialKey KeyEnter) Down _ _)
    = doesConfirm .~ True

eventHandler _
    = id
