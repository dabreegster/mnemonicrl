package PerlRL::Component::View;

use strict;
use warnings;
use Util;

use base "Exporter";
our @EXPORT = ("message", "setup_ui", "got_player");

use constant STUFF_LAYER => 3;

#use HexedUI::Interface;  # POE error

# Overload to determine the symbol and color of a particular tile.
sub HexedUI::Hexed::Map::render {
  my ($self, $tile) = @_;
  my ($symbol, $color);

  my $layers = GAME->{BDSMLayers};

  # Hide stuff in layers that we're not in -- it's more fun that way
  my $hide = 1 if $tile->{Layer} and !$tile->{LayerOff};

  my $light = !$self->{Map}{_Data}{superlight};   # Do we apply rules?
  my $layer = $tile->{Layers}[-1] || [0];

  if ($layer->[0] <= STUFF_LAYER and !$hide) {
    if (ref $tile->{Actor} eq "HASH") {
      # Probably some split-up flyweightedish sprite, grab directly.
      $symbol = $tile->{Actor}{Symbol};
      $color = $tile->{Actor}{Color};
    } elsif ($tile->{Actor}) {
      # Some agent, handle it
      ($symbol, $color) = $tile->{Actor}->display;
    } elsif ($tile->{Inv} and my ($item) = $tile->{Inv}->all) {
      ($symbol, $color) = $item->display;
    }
  }

  if (!$symbol and $layer->[0] <= 0) {
    $symbol = CFG->{Tilemap}{ $tile->{_} }{Symbol} // $tile->{_};
    $color = CFG->{Tilemap}{ $tile->{_} }{Color};
  }

  unless ($symbol) {
    # Fine, use the layer
    if ($layer->[0] == $layers->{symbol} and $tile->{LayerOff}) {
      # Keep the symbol -- unless its blank -- but dim it
      $symbol = $layer->[1] || " ";
      $color = "Black";
    } else {
      ($symbol, $color) = ($layer->[1], $layer->[2]);
      if ($layer->[0] == $layers->{name} or $layer->[0] == $layers->{hilite}) {
        $light = 0;
      } elsif ($layer->[0] == $layers->{snow}) {
        $light = 0;
        $color = "Black" unless $tile->{Lit} and $tile->{Lit} == 2;
      }
    }
  }

  if ($light) {
    # 0 = never seen, 1 = seen a while ago, 2 = seen now
    if ($tile->{Lit}) {
      $color = "Black" if $tile->{Lit} == 1 and !$self->{Map}{_Data}{nofovmemory};
    } else {
      $color = "black";
    }
  }

  if ($tile->{ColorLight}) {
    $symbol = "*" if $symbol eq " ";
    $color = $tile->{ColorLight};
  }

  return ($symbol, $color);
}

# Just print it, usually
sub message {
  my ($game, $channel, $msg, $obj, $caller) = @_;
  msg $channel => $msg;
}

# Gorgeous, no?
sub setup_ui {
  my $game = shift;

  # Create the default interface
  my $ui = cast HexedUI::Interface {
    Keymap => "Keymap",
    FPS    => CFG->{UI}{FPS},
    Bar => {
      Type    => "Form",
      At      => [0, 0],
      Size    => [4, "60%"],
      Border  => 1,
      Entries => [
        [[ Clock   => "[_:_]" ],
        [ Wait     => "Wait: _" ]],
        [[ YouHP   => "You: *", -bars => [10] ],
        [ ThemHP   => "_<grey>: *", -bars => [10] ]]
      ],
      Withs => {
        YouHP => sub { my $h = Player->{HP}; return ($h->value, $h->cap); },
        ThemHP => sub {
          my $m = UI->{Battling};
          if ($m->{ID} == -1) {
            return ("No Target", 0, 1);
          } else {
            my ($sym, $color) = $m->display;
            return ("<$color>$sym", $m->{HP}->value, $m->{HP}->cap);
          }
        },
      }
    },
    Main => {
      Type   => "Map",
      At	   => [4, 0],
      Size   => ["100% - 4", "60%"],
      #At     => [0, 0],
      #Size   => ["100%", "100%"],
      Border => "Green",
      Pad    => 1,
    },
    Status => {
      Type    => "Form",
      At      => [0, "60%"],
      Size    => [11, "40% + 1"],
      Border  => 1,
      Entries => [
        [[ Name => "_ [_] [_]" ]],
        [[ Rank => "<cyan>Rank:<grey> _ [_]" ]],
        [[ Coords => "<blue>At:<grey> _, _ (_)" ]],
        [[ HP => "<purple>HP:<grey> _/_", ],
         [ ESM => "<purple>ESM:<grey> _/_" ]],
        [[ Str => "<red>Str:<grey> _" ],
         [ Def => "<red>Def:<grey> _" ]],
        [[ Dext => "<green>Dext:<grey> _" ]],
        [[ Exp => "<cyan>Exp<grey>: _ (_ till next)" ]],
        [[ Weapon => "<Red>Wielding:<grey> _" ]],
        [[ Mask => "<orange>Wearing:<grey> _" ]]
      ],
      Withs => {
        Rank   => sub { my $p = Player; ($p->Class, $p->{Level}) },
        Coords => sub { my $p = Player; ($p->{Y}, $p->{X}, $p->{Map}{Depth}) },
        HP     => sub { my $p = Player; ($p->{HP}{Now}, $p->{HP}{Cap}) },
        ESM    => sub { my $p = Player; ($p->{ESM}{Now}, $p->{ESM}{Cap}) },
        Str    => sub { my $p = Player; $p->{Str}->value },
        Def    => sub { my $p = Player; $p->{Def}->value },
        Dext   => sub { my $p = Player; $p->{Dext}->value },
        Exp    => sub { my $p = Player; ($p->{Exp}, $p->nextexp) },
        Weapon => sub { my $w = Player->{Equipment}{Weapon}; $w ? $w->name : "Unarmed"; },
        Mask   => sub { my $m = Player->{Equipment}{Mask}; $m ? $m->name : "Maskless"; }
      }
    },
    Msgs => {
      Type   => "Msg",
      At     => ["11", "60%"],
      Size   => ["100% - 11 - 3", "40% + 1"],
      Border => 1
    },
    Prompt => {
      Type   => "Prompt",
      At     => ["100% - 3", "60%"],
      Size   => [3, "40% + 1"],
      Border => 1,
      MaxIn  => 500
    }
  };
  $ui->keymap("../Keymap"); # ui stuff
  $game->{UI} = $ui;
  msg(-set => $ui->{Msgs});
  $ui->{Prompt}->start_prompt;
}

# Whenever we determine the player object, run through a bunch of UI stuff
sub got_player {
  my ($game, $us) = @_;

  $game->changemap($us->{Map});

  # And do the UI
  UI->{Main}->light($us);
  UI->{Main}->focus($us);
  UI->{Main}->drawme;
  UI->{Status}->update(Name =>
    $us->{Name}, "<" . $us->{Color} . ">" . $us->{Symbol} . "<grey>", $us->{Gender}
  );
  UI->{Status}->update($_) foreach ("Coords", "HP", "ESM", "Str", "Def", "Dext", "Rank",
                                    "Exp", "Weapon", "Mask");
  UI->{Battling} = { ID => -1 };
  UI->{Bar}->update("YouHP");
  UI->{Bar}->update("ThemHP");
}

package Game::Attack;
no warnings "redefine";
use Util;

sub cb_pts {
  my ($attack, $heap, $ranger) = @_;
  my $fx = $attack->{Draw}; $fx = $fx->($ranger) if ref $fx eq "CODE";
  my @pts = @{ $heap->{pts} };

  my $lag = $attack->{PtLag} // CFG->{Misc}{ProjectileLag};
  my @chain = @pts if $fx->[2];   # Make a copy to erase
  $ranger->{Map}->mod(@{ $pts[0] }, effect => @$fx);
  GAME->schedule(
    -do   => sub {
      $fx->[2] ? shift @pts : $ranger->{Map}->del(@{ shift @pts }, "effect"); # Chained?
      unless (@pts) {
        # Erase the chain if there is one
        $ranger->{Map}->del(@$_, "effect") foreach @chain;
        UI->{Main}->drawme;
        return "STOP";
      }
      $ranger->{Map}->mod(@{ $pts[0] }, effect => @$fx);
      UI->{Main}->drawme;
      return $lag;
    },
    -id    => "projectile_$ranger->{ID}_" . tmpcnt,
    -tags  => ["map", "ui", "projectile"],
    -delay => $lag
  );
}

sub cb_rays {
  my ($attack, $heap, $ranger) = @_;
  my $fx = $attack->{Draw}; $fx = $fx->($ranger) if ref $fx eq "CODE";
  my @rays = @{ $heap->{rays} };

  my @erase;
  my $lag = $attack->{RayLag} // CFG->{Misc}{ProjectileLag};
  GAME->schedule(
    -do   => sub {
      # delete last? $self->{Map}->del($y, $x, "effect");
      unless (@rays) {
        $ranger->{Map}->del(@$_, "effect") foreach @erase;
        UI->{Main}->drawme;
        return "STOP";
      }

      foreach my $pt (@{ shift @rays }) {
        $ranger->{Map}->mod(@$pt, effect => @$fx);
        push @erase, $pt;
      }
      UI->{Main}->drawme;
      return $lag;
    },
    -id    => "explode_" . tmpcnt,
    -tags  => ["map", "ui", "explosion"],
    -delay => $lag
  );
}

sub cb_targets {
  my ($attack, $heap, $attacker, @targets) = @_;
  if ($attacker->player and UI->{Battling}{ID} != $targets[0]->{ID}) {
    UI->{Battling} = $targets[0];
    $targets[0]->{HP}->modded;
  }
}

package Game::Stat;
use Util;

sub modded {
  my $stat = shift;
  if (Player->{ID} == $stat->{Owner}) {
    UI->{Status}->update($stat->{Name});
    UI->{Bar}->update("YouHP");
  } elsif (UI->{Battling}{ID} == $stat->{Owner} and $stat->{Name} eq "HP") {
    UI->{Bar}->update("ThemHP");
  }
}

42;
