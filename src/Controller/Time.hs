{-# LANGUAGE DisambiguateRecordFields, NamedFieldPuns, RecordWildCards       #-}
{-# LANGUAGE ParallelListComp, FlexibleContexts                              #-}

module Controller.Time (
    timeHandler
) where

import Control.Lens
import Control.Monad
import Control.Monad.State
import Data.Maybe
import System.Random

import Helper
import Highscores
import Model

import Controller.MenuUpdate

import Graphics.Gloss hiding (Point)

-- | Time handling

--This is where we will change the gameworld (Update)
--time is the passed time in seconds (gameTime)
timeHandler :: Float -> World -> IO World
timeHandler time world = if world^.endTimer > 0 then do
                             let nWorld = execState reduceEndTimer world
                             if (nWorld^.endTimer) < 0 then
                                 execStateT diePlayer nWorld
                             else
                                 return $ execState (changeWorld time) nWorld
                         else if world^.player^.lives <= 0 then
                             return $ execState setEndTimer world
                         else if world^.isHighSet then return $ execState (changeWorld time) world
                         else do hsWorld <- execStateT setWorldHighscore world
                                 return $ execState (changeWorld time) hsWorld
                                 
-- End of the world: a few seconds where the player is dead and we 
-- haven't returned to the main menu yet
                      
setEndTimer :: MonadState World m => m ()
setEndTimer = endTimer .= 60

reduceEndTimer :: MonadState World m => m ()
reduceEndTimer = endTimer -= 1

--Functions needed for using states
--Important types:
--StateT    :: (s -> m(a,s))  -> StateT s a
--State     :: StateT s Identity
--(State    :: (s -> (a,s))   -> State s a)
--runState  :: State s a -> s -> (a, s) 
--execState :: State s a -> s -> s
--(In runState, the s given is a starting state, in our case the current world)
--(Identity is a monad, that returns the normal value, runIdentity :: a)

--Change the world in the MonadState
changeWorld :: MonadState World m => Float -> m ()
changeWorld time = do curState <- use gameState
                      if curState == InMenu then
                          updateMenu
                      else do
                          tickTime   .= time
                          passedTime += time
                          rotatePlayer
                          movePlayer
                          shootPlayer
                          moveBullets
                          updateBullets
                          spawnBonuses
                          pickupBonuses
                          spawnEnemies
                          moveEnemies
                          updateParticles
                      resetKeys
                      handleStars

--Sets the highscore var in the world
setWorldHighscore :: StateT World IO ()
setWorldHighscore = do hs <- lift getHighscore
                       highscore .= hs
                       isHighSet .= True

--Changes the world for when the player dies
diePlayer :: StateT World IO ()
diePlayer = do scoreT <- use $ player.score
               better <- lift $ checkHighscore scoreT
               newSeed <- getRandomR (0, 100000)
               put $ initial newSeed -- Reset state
               when better $ do lift $ saveHighscore scoreT
                                highscore      .= scoreT
                                isNewHighscore .= True
               menu.hasDiedBefore .= True
               player.score       .= scoreT --Set score again
                      
--Reset some keys that should only be handled on press
resetKeys :: MonadState World m => m()
resetKeys = do doesConfirm    .= False
               doesSelectPrev .= False
               doesSelectNext .= False

--Move the player if needed
movePlayer :: MonadState World m => m ()
movePlayer = do moveAction <- use movementAction
                when (moveAction == Thrust) $ do
                    p                <- use player
                    let newDir        = moveDir (p^.playerDir) (p^.playerSpeed) (p^.playerPos)
                    particles        %= (newParticle (p^.playerPos) 10 yellow :)
                    player.playerPos .= checkPosition newDir (p^.playerSize)
                    
--Checks whether the position with given offset is still inside the screen, if not returns the new position                  
checkPosition :: Point -> Float -> Point
checkPosition pos off = case outsideBounds pos off of
                            East  -> (x -~ screenWidth  + off) pos
                            West  -> (x +~ screenWidth  + off) pos
                            North -> (y -~ screenHeight + off) pos
                            South -> (y +~ screenHeight + off) pos
                            None  -> pos

--Checks whether given point is outside the screen (with given offset to each side)                  
outsideBounds :: Point -> Float -> Side
outsideBounds p offset | p^.x - offset > 0.5 * screenWidth   = East
                       | p^.x + offset < -0.5 * screenWidth  = West
                       | p^.y - offset > 0.5 * screenHeight  = North
                       | p^.y + offset < -0.5 * screenHeight = South
                       | otherwise                           = None
 
--Rotate the player if needed 
rotatePlayer :: MonadState World m => m ()
rotatePlayer = do rAction <- use rotateAction
                  speed   <- use $ player.playerSpeed
                  case rAction of
                    RotateLeft  -> player.playerDir -= (speed / 180) * pi
                    RotateRight -> player.playerDir += (speed / 180) * pi 
                    NoRotation  -> return ()

--Shoots if the player wants to shoot and the time since the last shot is long enough                    
shootPlayer :: MonadState World m => m ()
shootPlayer = do p     <- use player
                 shoot <- use shootAction
                 player.shootTime -= 1
                 when (shoot == Shoot && p^.shootTime <= 0 && p^.invincibleTime <= 0) $ do
                    bullets          %= (newBullet (p^.playerPos) (p^.playerDir) :)
                    player.shootTime .= p^.baseShootTime
                    
--Moves all bullets
moveBullets :: MonadState World m => m ()
moveBullets = bullets.traversed %= moveBullet

--Moves a bullet
moveBullet :: Bullet -> Bullet
moveBullet b = b & bulPos .~ moveDir (b^.bulDir) (b^.bulSpeed) (b^.bulPos)

-- Spawn new bonuses now and then
spawnBonuses :: MonadState World m => m ()
spawnBonuses = do spawner <- use bonusSpawner
                  bonusSpawner.timeToNext -= 1
                  when (spawner^.timeToNext <= 0) $ do
                      playerPos <- use $ player.playerPos
                      spawnPos <- getRandomSpawnPoint
                      bonuses %= (newBonus spawnPos :)
                      bonusSpawner.timeToNext += spawner^.interval

-- Have the player pick up bonuses
pickupBonuses :: MonadState World m => m ()
pickupBonuses = do playerPos  <- use $ player.playerPos
                   playerSize <- use $ player.playerSize
                   currentBonuses <- use bonuses
                   let collidingBonuses = filter (\b -> pointDistance playerPos (b^.bonusPos) < bonusSize + playerSize) currentBonuses
                   when (not $ null collidingBonuses) $ do
                       player.scoreMul += 1
                       bonuses %= filter (not . (`elem` collidingBonuses)) -- Destroy any colliding enemies

--Checks whether bullets collide and updates the lifetime and deletes the bullet if it times out
updateBullets :: MonadState World m => m ()
updateBullets = do es <- use enemies
                   bs <- use bullets
                   bn <- use bonuses
                   let colEnemy  = unzip $ mapMaybe (collideWith es) bs
                   let colBonus  = unzip $ mapMaybe (collideWith bn) bs
                   let infst c x = x `elem` (fst c)
                   let insnd c x = x `elem` (snd c)
                   let timeout b = b^.bulTime <= 0
                   player.scoreMul += length (snd colBonus)
                   sMul         <- use $ player.scoreMul
                   player.score += length (fst colEnemy) * sMul
                   bullets      .= filter (\b -> not (infst colEnemy b || infst colBonus b || timeout b)) bs
                   explodeEnemies $ snd colEnemy
                   es2 <- use enemies --We can have spawned new enemies
                   enemies      .= filter (not . (insnd colEnemy)) es2
                   bonuses      .= filter (not . (insnd colBonus)) bn
                   bullets.traversed.bulTime -= 1                

-- Let enemies in the monad explode
explodeEnemies :: MonadState World m => [Enemy] -> m ()
explodeEnemies []           = return ()
explodeEnemies (thisE:allE) = do explodeEnemies allE
                                 particles %= (map (\p -> newParticle (p `addPoints` (thisE^.enemyPos)) 10 red) (thisE^.enemyEdges) ++)
                                 -- Spawn new enemies if the enemies was very big
                                 when (thisE^.enemySize > 30) $ do
                                     startingAngle <- getRandomR (0, pi / 2)
                                     spawnE startingAngle
                                     spawnE $ startingAngle + pi / 2
                                     spawnE $ startingAngle + pi
                                     spawnE $ startingAngle + pi * 1.5
                            where
                                spawnE angle
                                 = do segmentNum <- getRandomR (5 :: Int, 10)
                                      generator  <- use rndGen
                                      let newSize = thisE^.enemySize / 2
                                      let edgePoints = getEnemyPoints newSize segmentNum generator
                                      enemies %= (newEnemy (moveDir angle newSize (thisE^.enemyPos)) angle edgePoints newSize :)

--Class for objects you can collide with
class Collider a where
    --Checks if there is a collision with a Bullet and returns it
    collideWith :: [a] -> Bullet -> Maybe (Bullet, a)
    
--Instance to collide enemies with bullets
--Use enemy size * 1.2 because we use an optimistic hitbox (enemies can be a bit
-- bigger than their size)
instance Collider Enemy where
    collideWith enemies b | filtered == [] = Nothing
                          | otherwise      = Just (b, (head filtered))
                          where filtered = filter (\e -> pointDistance (e^.enemyPos) (b^.bulPos) < (e^.enemySize * 1.3)) enemies

--Instance to collide bonuses with bullets                          
instance Collider Bonus where
    collideWith bonus b | filtered == [] = Nothing
                        | otherwise      = Just (b, (head filtered))
                        where filtered = filter (\bo -> pointDistance (bo^.bonusPos) (b^.bulPos) < bonusSize) bonus

-- Spawn new enemies every now and then
spawnEnemies :: MonadState World m => m ()
spawnEnemies = do spawner <- use enemySpawner
                  enemySpawner.timeToNext -= 1
                  when (spawner^.timeToNext <= 0) $ do
                      playerPos  <- use $ player.playerPos
                      spawnPos   <- getRandomSpawnPoint
                      thisSize   <- getRandomR (15, 45)
                      segmentNum <- getRandomR (5 :: Int, 15)
                      generator  <- use rndGen
                      let edgePoints = getEnemyPoints thisSize segmentNum generator
                      enemies %= (newEnemy spawnPos (pointDirection spawnPos playerPos) edgePoints thisSize :)
                      enemySpawner.timeToNext += spawner^.interval

getEnemyPoints :: RandomGen g => Float -> Int -> g -> [Point]
getEnemyPoints size num g
    = helper num g
    where helper 0 _   = []
          helper i gen = (moveDir ((fromIntegral i) / (fromIntegral num) * 2 * pi) (size * val) $ Point {_x = 0, _y = 0}) : (helper (i - 1) newGen)
                          where (val, newGen) = randomR (1, 1.3) gen

-- Move the enemies in the world
moveEnemies :: MonadState World m => m ()
moveEnemies = do playerPos  <- use $ player.playerPos
                 playerSize <- use $ player.playerSize
                 invcT      <- use $ player.invincibleTime
                 enemies.traversed %= moveEnemy playerPos
                 -- Check if any enemies collide with the player (if the player isn't invincible)
                 if invcT > 0 then
                     player.invincibleTime -= 1
                 else do
                     currentEnemies <- use enemies
                     let collidingEnemies = filter (\e -> pointDistance playerPos (e^.enemyPos) < (e^.enemySize) + playerSize) currentEnemies
                     -- Collide with player
                     when (not $ null collidingEnemies) $ do
                         player.scoreMul       .= 1
                         player.lives          -= 1
                         player.invincibleTime += invincibleTimeAfterCollision
                         explodeEnemies collidingEnemies
                         enemies %= filter (not . (`elem` collidingEnemies)) -- Destroy any colliding enemies
                         -- Spawn explosion particles
                         replicateM_ 100 $ do
                             dir        <- getRandomR (0, 2 * pi)
                             dist       <- getRandomR (0, playerSize)
                             let partPos = moveDir dir dist playerPos
                             particles  %= (newParticle partPos 10 white :)

-- Move a single enemy (needs the player position for tracking enemies)
moveEnemy :: Point -> Enemy -> Enemy
moveEnemy playerPos e
    = e & enemyPos .~ if e^.movementType == FixedDirection then
                          checkPosition (moveDir (e^.enemyDir) 5 (e^.enemyPos)) (e^.enemySize)
                      else
                          moveTo 5 playerPos $ e^.enemyPos

-- Move stars and spawn new ones
handleStars :: MonadState World m => m ()
handleStars = do stars.traversed %= (\star -> star & starPos . x -~ (star^.starSpeed))
                 stars %= filter (\star -> star^.starPos.x > -screenWidth / 2)
                 shouldSpawnStar <- getRandomR (0 :: Float, 1)
                 when (shouldSpawnStar < starSpawnChance) $ do
                     newStarPos      <- getRandomR (-screenHeight / 2, screenHeight / 2)
                     thisSpeed       <- getRandomR (1, 6)
                     stars %= (newStar (Point { _x = screenWidth / 2, _y = newStarPos}) thisSpeed :)

-- Make the particles smaller
updateParticles :: MonadState World m => m ()
updateParticles = do particles.traversed.partSize -= 1
                     particles %= filter (\p -> p^.partSize > 0)

-- Get a random point at a certain minimum distance from the player
getRandomSpawnPoint :: MonadState World m => m (Point)
getRandomSpawnPoint = do pPos   <- use $ player.playerPos
                         spawnX <- getRandomR (-screenWidth / 2, screenWidth / 2)
                         spawnY <- getRandomR (-screenHeight / 2, screenHeight / 2)
                         let spawnPos = Point {_x = spawnX, _y = spawnY}
                         if pointDistance spawnPos pPos > 250 then
                             return spawnPos
                         else
                             getRandomSpawnPoint

-- Get a random value using the world state
getRandomR :: (MonadState World m, Random a) => (a, a) -> m (a)
getRandomR range = do generator <- use rndGen
                      let r = randomR range generator
                      rndGen .= snd r
                      return $ fst r