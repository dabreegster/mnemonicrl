package Game::StdLib::Character::Monster;

use strict;
use warnings;
use Util;

use base "Game::StdLib::Character";
__PACKAGE__->announce("Monster");

__PACKAGE__->classdat(
  Pack => 0,
  Rank => 1,
  Speed => 1,
  Stats => {
    HP => 1,
    HP_Rate => 1,
    Def => 1,
    Dext => 1
  },
  Descr => "An unknown creature from anyone's mind..."
);

# Scary!
sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts);

  $self->_construct(\%opts => "ExpWorth");
  $self->{Goal} = ["Sleeping"];

  my $ood = $self->ood($self->{Map}{Depth});
  $self->{Level} ||= max(1, $ood);
  my $exp = $self->Rank * CFG->{Scale}{Experience};
  $exp += $ood if $ood > 0; # Early
  $self->{ExpWorth} ||= random(
    $exp - CFG->{Scale}{ExpDeviance}, $exp + CFG->{Scale}{ExpDeviance}
  );

  return $self;
}

sub WhenDescribe {
  my $self = shift;
  my $chance = 100 - CFG->{DunGen}{RareMonster} * abs $self->ood($self->{Map}{Depth});
  return ("Rank: " . $self->Rank . ", $chance% here");
}

# Somebody has tread within our proximity...
sub WhenDisturbed {
  my ($self, $idiot) = @_;

  # Switch targets eagerly, and always give encouragement
  my $awake = 1 unless $self->{Goal}[0] eq "Sleeping";
  $self->{LastSeen} = time;
  $self->{Goal} = ["Chasing", $idiot] unless $self->{Goal}[0] eq "Attacking";
  $self->schedule(
    -do => "AI_turn", -id => "ai_$self->{ID}", -tags => ["ai"]
  ) unless $awake;
}

###########################################################################################

# TODO: changing targets, config behaviors, when to attack, not spamming an attack (speed)

# What to do next?
sub AI_turn {
  my $self = shift;

  # We can change states here and immediately do something
  while (1) {
    if ($self->{Goal}[0] eq "Sleeping") {
      # We can redirect here from other states
      return "STOP";
    } elsif ($self->{Goal}[0] eq "Chasing") {
      my $goal = $self->{Goal}[1];
      if ($goal->{Dead}) {
        $self->{Goal} = ["Sleeping"];
        next;
      }
      # Give up eventually till we're re-awoken
      if (time() - $self->{LastSeen} > CFG->{Misc}{GiveUpAI}) {
        $self->{Goal} = ["Sleeping"];
        delete $self->{LastSeen};
        next;
      }

      # Have we caught up?
      if ($self->adj($goal)) {
        $self->{Goal}[0] = "Attacking";
        next;
      }
      my @best = $self->{Map}->bestadj(
        from   => [$self->{Y}, $self->{X}],
        diag   => 1,
        actors => 0,
        rank   => "highest",
        score  => sub {
          my ($y, $x) = @_;
          $self->{Map}{Map}[$y][$x]{Scent}{ $goal->{ID} };
        }
      );

      if (@best) {
        $self->go(@best);
      } else {
        debug "@{[$self->id]} stuck!";
        $self->{Lag} = 1; # For now
      }

      return $self->{Lag} || 1; # Even if it's a realtime map, dont spam them
    } elsif ($self->{Goal}[0] eq "Attacking") {
      my $goal = $self->{Goal}[1];
      if ($goal->{Dead}) {
        $self->{Goal} = ["Sleeping"];
        next;
      }
      unless ($self->adj($goal)) {
        $self->{Goal}[0] = "Chasing";
        next;
      }
      my $attack = choosernd(@{ $self->{Moveset}{adj} });
      $self->{Goal}[0] = "Chasing", return 1 if GAME->{DebugSafety};
      if ($attack) {
        $self->attack($attack, $goal);
      } else {
        debug "@{[$self->id]} has no attacks yet. ah well";
        $self->lag(0.5);  # Eh, for now
      }
      return $self->{Lag} || 1; # Even if it's a realtime map, dont spam them
      #return $self->{Lag} + CFG->{Scale}{MonsterLag};
    }
  }
}

###########################################################################################

sub BEFORE_death {
  my ($self, $heap) = actargs @_;
  return unless GAME->fullsim;
  # Drop items!
  foreach ($self->{Inv}->all) {
    #next if percent(50);  # TODO: better than this?
    $self->drop($_);
  }
  my $corpse = GAME->make("corpse", Of => $self);
  $self->{Map}->inv($self->{Y}, $self->{X}, "add", $corpse);
  $heap->{Corpse} = $corpse;
  $self->fxn("OnCorpse", $corpse);
  1;  # Don't let fxn return something mean.
}

42;
