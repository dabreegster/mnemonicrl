package Cfg;

use strict;
use warnings;

our $cfg = bless {
  News => [
    "Bah, just see http://mnemonicrl.blogspot.com/"
  ],
  Scale => {
    # Stats range from 1 to 20
    # Speed and Rates range from 1 to 5
    # Character classes start with stats from 1 to 5
    # Monster damage ranges from 10 now, but I haven't coded all attacks
    # Items rank from 1 to 10 (I'm thinking DLvlRatio = 2 for now)
    # Power and Accuracy range from 1 to 20


    DLvlRatio    => 2,   # So X dungeon levels where rank 1's are standard

    # Character stuff
    StatDeviance => 4,   # So random(base - devi, base + devi)
    HP           => 5,
    HP_Rate      => 1,
    HP_Rate_Max  => 4,   # Higher rate is "faster"
    ESM          => 3,
    ESM_Rate     => 2,
    ESM_Rate_Max => 3,   # Higher rate is "faster"
    Str          => 3,
    Def          => 1.8,
    Dext         => 3,
    Speed        => .5,
    SpeedWeapon  => .15,
    Speed_Max    => 5,   # Higher speed is less lag time
    Experience   => 3,
    ExpDeviance  => 2,

    # Item stuff
    Power        => 2.5,
    Accuracy     => 2,
    ItemDeviance => 3,

    # Attack stuff
    Damage       => 2,
    OuchDeviance => 3,
    DRatio       => 4,
    MonsterLag   => 2,    # +, not a ratio!
  },
  Snow => {
    SpawnWidth => 20,
    Period     => [4, 8],
    SpawnRate  => 0.8,
    SlowSnow   => .20,
    FastSnow   => .15
  },
  UI => {
    #NameTime  => 300,   # How long to display name over somehow
    #NameDelay => 30,    # How long before we display a name banner again
    chatColor   => "Cyan",
    errColor    => "Red",
    seeColor    => "green",
    battleColor => "purple",
    plain       => "grey",
    FPS         => 1.0 / 30 # Sleep for this long. aka 30 FPS
  },
  Particles => {
    fire => {
      Spawn  => 0.25,
      Move   => 0.2,
      Symbol => ["(", ")"],
      Color  => "Red"
    },
    smoke => {
      Spawn  => 0.25,
      Move   => 0.2,
      Symbol => ["O", "o"],
      Color  => "grey"
    },
    greenfire => {
      Spawn  => 0.25,
      Move   => 0.2,
      Symbol => ["(", ")"],
      Color  => "Green"
    }
  },
  DunGen => {
    # Cruel, I know
    RareItem     => 45,
    RareMonster  => 35,
    NumBaddies   => [10, 12],  # Per level
    NumStuff     => [5, 10],
    DungeonSize  => [50, 150],
    CaveSize     => [50, 100]
  },
  Misc => {
    ProjectileLag => 0.1,
    BeltSpeed     => 0.1,
    GiveUpAI      => 15,  # seconds
  },
  Game => {
    Server => "jigstar.ath.cx",
    Port   => 2302
  },
  Tilemap => {
    '#' => {
      Name        => "wall",
      Permeable   => 0,
      Color       => "orange",
      Transparent => 0
    },
    '.' => {
      Name        => "ground",
      Permeable   => 1,
      Color       => "grey",
      Transparent => 1
    },
    '<' => {
      Name        => "upstairs",
      Permeable   => 1,
      Color       => "white",
      Transparent => 1
    },
    '>' => {
      Name        => "downstairs",
      Permeable   => 1,
      Color       => "white",
      Transparent => 1
    },
    '~' => {
      Name        => "water",
      Permeable   => 1,
      Color       => "Blue",
      Transparent => 1
    },
    '=' => {
      Name        => "water particle",
      Symbol      => "~",
      Permeable   => 1,
      Color       => "cyan",
      Transparent => 1
    },
    ' ' => {
      Name        => "empty space",
      Permeable   => 1,
      Color       => "grey",
      Transparent => 1
    },
    '_' => {
      Name        => "conveyor belt",
      Permeable   => 1,
      Color       => "grey",
      Transparent => 1
    },
    '+' => {
      Name        => "door",
      Permeable   => 1,
      Color       => "white",
      Transparent => 0
    },
  },
  Hotel => {
    ClockMin => 15, # one game-minute lasts 15 player-seconds, unless we mod timeflow...
    Pots     => 15,
    Ingredients => 45
  },
}, __PACKAGE__;

my $profiles = {
  Snow => {
    Light  => {
      SpawnWidth => 20,
      Period     => [4, 8],
      SpawnRate  => 0.8,
      SlowSnow   => .20,
      FastSnow   => .15
    },
    Medium => {
      SpawnWidth => 10,
      Period     => [3, 6],
      SpawnRate  => 0.5,
      SlowSnow   => .15,
      FastSnow   => .10
    },
    Heavy  => {
      SpawnWidth => 8,
      Period     => [3, 6],
      SpawnRate  => 0.5,
      SlowSnow   => .10,
      FastSnow   => .05
    }
  }
};

# Select a certain set of options
sub set {
  my ($self, $options, $style) = @_;
  my %data = %{ $profiles->{$options}{$style} };
  @{ $self->{$options} }{keys %data } = values %data;
}
