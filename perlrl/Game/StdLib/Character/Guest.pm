package Game::StdLib::Character::Guest;

use strict;
use warnings;
use Util;

use base "Game::StdLib::Character";
__PACKAGE__->announce("GuestNPC");

use BDSM::Vector;

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
  Descr => "A soldier -- perhaps even a general -- in an army of finely-dressed, well-mannered seconds. He/she ticks about his/her route like a battle-weary mailman."
);

# Scary!
sub new {
  my ($class, %opts) = @_;

  my $map = GAME->{Levels}{ $opts{start} };
  my $self = $class->SUPER::new(%opts, Map => $map);

  # TODO when time starts over, technically we should obey continuity and wind up where we
  # started and have the same general route?

  
  # Plan route.
  my @route;
  my %visited;
  my $cur = delete $opts{start};
  $visited{$cur} = 1;

  # Lazy guys or avid spazzticles? random decides.
  for (1 .. random(8, 25)) {
    my $next = (sort {
      my $A = $visited{$a} // 0; my $B = $visited{$b} // 0;
      return $A <=> $B or choosernd(-1, 1); # Randomly distribute among equally unvisited
    } shuffle(keys %{ GAME->{LogicMap}{$cur} }))[0];
    push @route, [$next, @{ GAME->{LogicMap}{$cur}{$next}[0] } ];
    # TODO cheating above. always shoot for first staircase if there are multiple routes
    # from $cur -> $next. This should generally be OK as long as the stairs are right next
    # to each other...
    $cur = $next;
    $visited{$cur} ||= 0;
    $visited{$cur}++;
  }
  $self->{Route} = \@route;
  debug \@route;

  $self->{Goal} = ["Going", @{ shift @{ $self->{Route} } }];

  $self->schedule(
    -do    => "AI_turn",
    -id    => "ai_$self->{ID}",
    -tags  => ["ai"],
    -delay => random(1, 100) / 100  # Cooler when the army isn't quite so robotic
  );

  return $self;
}

sub WhenDescribe {
  my $self = shift;
  return ("A guest.");
}

# Somebody has tread within our proximity...
sub WhenDisturbed {
  my ($self, $idiot) = @_;
  # TODO not actually triggered yet
}

###########################################################################################

sub AI_turn {
  my $self = shift;

  # Simple pattern... go somewhere, idle there for a bit...

  while (1) {
    if ($self->{Goal}[0] eq "Going") {
      my (undef, $where, $y, $x) = @{ $self->{Goal} };

      if ($self->{Y} == $y and $self->{X} == $x) {
        $self->changedepth;
        $self->{Goal} = ["Pacing"];

        # so we have N places to visit in some chunk of time. Spend "approx" an even chunk
        # of time in each place.
        my $idle = random(0, 30) + GAME->{HotelClock}->mins_left / scalar(@{ $self->{Route} });
        $self->schedule(
          -do    => sub {
            $self->{Goal} = ["Going", @{ shift @{ $self->{Route} } }] if @{ $self->{Route} };
          },
          -id    => "ai_$self->{ID}_idler",
          -tags  => ["ai"],
          -delay => $idle * CFG->{Hotel}{ClockMin}
        );

        next;
      }

      my @best = $self->{Map}->bestadj(
        from   => [$self->{Y}, $self->{X}],
        diag   => 1,
        actors => 0,
        rank   => "lowest",
        score  => sub { $self->{Map}->tile(@_)->{Scents}{$where} }
      );
      if (@best) {
        $self->go(@best);
      } else {
        debug $self->id . " stuck :(";
      }
      last;
    } elsif ($self->{Goal}[0] eq "Pacing") {
      unless ($self->{Goal}[1]) {
        my $tag = choosernd(keys %{ $self->{Map}{MaxScent} });
        my $max = $self->{Map}{MaxScent}{$tag};
        my $score = random($max / 2, $max);
        # So pace by wandering away from a staircase. Should be realistic enough? Data's
        # already there, so may as well abuse it.
        $self->{Goal} = ["Pacing", $tag, $score];
      }
      my (undef, $tag, $score) = @{ $self->{Goal} };

      # Have we reached our goal? Pick another!
      if (abs($score - $self->tile->{Scents}{$tag}) <= 2) {
        msg battle => $self->id . " bored, pacing again";
        $self->{Goal} = ["Pacing"];
        next;
      }

      my @best = $self->{Map}->bestadj(
        from   => [$self->{Y}, $self->{X}],
        diag   => 1,
        actors => 0,
        rank   => "lowest",
        # Even when the diffusion is orthogonal and not diagonal, still can get small
        # pockets that create a loop... or we choose from a path that tends towards our
        # goal scent but only briefly. Either way, random deviance can fix.
        score  => sub {
          abs($score - $self->{Map}->tile(@_)->{Scents}{$tag}) + random(1, 10);
        }
      );
      if (@best) {
        $self->go(@best);
        my $str = "$best[0],$best[1]";
        $self->{Backtrack}{$str} ||= 0;
        $self->{Backtrack}{$str}++;
      } else {
        debug $self->id . " stuck PACING :(";
      }
      last;
    }
  }

  return random(90, 250) / 100;
  #return $self->{Lag} // 1.0;
}

# Tempish, just dump our goal.
sub describe {
  my $self = shift;
  return join(", ", @{ $self->{Goal} // ["Dunno, the server has it"] });
}

42;
