{-# LANGUAGE TemplateHaskell, DisambiguateRecordFields, NamedFieldPuns #-}

module Model where

import Control.Lens
import System.Random

-- | Game state

--Basic data of World, add other datatypes used below
data World = World { _rndGen           :: StdGen
                   , _rotateAction     :: RotateAction
                   , _movementAction   :: MovementAction
                   , _shootAction      :: ShootAction
                   , _player           :: Player
                   , _enemies          :: [Enemy]
                   , _passedTime       :: Double
                   , _enemySpawner     :: EnemySpawner
                   } deriving (Show)
    
data RotateAction   = NoRotation | RotateLeft | RotateRight deriving (Show)
data MovementAction = NoMovement | Thrust                   deriving (Show)
data ShootAction    = Shoot      | DontShoot                deriving (Show)

data EnemyMovementType = FixedDirection | FollowPlayer      deriving (Show, Eq)

--TODO: Add more datatypes here (player/enemy/etc.)
data Player = Player { _playerPos :: Point
                     , _playerSize:: Float
                     , _lives     :: Int
                     , _score     :: Int
                     , _scoreMul  :: Int
                     } deriving (Show)
data Enemy  = Enemy  { _enemyPos  :: Point
                     , _movementType :: EnemyMovementType 
                     , _enemyDir  :: Float
                     , _enemySize :: Float
                     } deriving (Show)
data Point  = Point  { _x         :: Float
                     , _y         :: Float
                     } deriving (Show)

-- Contains data needed for spawning enemies
-- only the time to next at the moment, but this could include much more
-- (such as the enemy type, patterns, etc.)
data EnemySpawner = EnemySpawner { _timeToNext :: Float
                                 , _interval   :: Float } deriving (Show)

--Add lenses below (must be after defining datatypes)
--(TemplateHaskell can do this automatically with makeLenses,
-- this will make a lens for all _ vars in the datatype )
makeLenses ''World
makeLenses ''Player
makeLenses ''Enemy
makeLenses ''Point
makeLenses ''EnemySpawner

--Returns the starting world of the game based on given seed
initial :: Int -> World
initial seed = World { _rndGen         = mkStdGen seed
                     , _rotateAction   = NoRotation
                     , _movementAction = NoMovement
                     , _shootAction    = DontShoot
                     , _player         = newPlayer
                     , _enemies        = []
                     , _passedTime     = 0
                     , _enemySpawner   = newEnemySpawner
                     }
                      
--Returns the starting values for a player
newPlayer :: Player
newPlayer = Player { _playerPos  = Point {_x = 0, _y = 0}
                   , _playerSize = 10
                   , _lives      = 3
                   , _score      = 0 
                   , _scoreMul   = 1
                   }
                   
--Returns a new enemy at a given (random) point, moving in a given dir
newEnemy :: Point -> Float -> Enemy
newEnemy p d = Enemy { _enemyPos     = p
                     , _enemySize    = 5
                     , _movementType = FixedDirection
                     , _enemyDir     = d
                     }

newFollowingEnemy :: Point -> Enemy
newFollowingEnemy p = set movementType
                          FollowPlayer
                          $ newEnemy p 0

newEnemySpawner :: EnemySpawner
newEnemySpawner = EnemySpawner { _timeToNext = 0
                               , _interval   = 60 }







