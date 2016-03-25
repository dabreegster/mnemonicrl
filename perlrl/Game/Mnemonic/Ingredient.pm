package Game::Mnemonic::Ingredient;

use strict;
use warnings;
use Util;

use base "Game::StdLib::Character::Monster";
__PACKAGE__->announce("Ingredient");

use BDSM::Vector;

sub new {
  my ($class, %opts) = @_;

  my $self = $class->SUPER::new(%opts,
    Symbol => choosernd("a" .. "z"),
    Color => "Green/faded"
  );

  return $self;
}

sub id {
  my $self = shift;
  return $self->type . "_$self->{ID}_$self->{Symbol}";
}

# What to do next?
sub AI_turn {
  my $self = shift;

  # And go back to sleep when we're safe :P
  if (time() - $self->{LastSeen} > CFG->{Misc}{GiveUpAI}) {
    $self->{Goal} = ["Sleeping"];
    delete $self->{LastSeen};
    delete $self->{LastFleeFrom};
    return "STOP";
  }

  # Forget the goal crap the generic monster handler sets, we just run from shit
  my $ohno = $self->{Goal}[1];
  $self->{LastFleeFrom} //= [-1, -1]; # If it's not set, we're just waking up -- so
                                      # backtracking is fine
  my $moved = ($self->{LastFleeFrom}[0] != $ohno->{Y} or $self->{LastFleeFrom}[1] != $ohno->{X});
  my @go = $self->{Map}->bestadj(
    diag  => 0,
    from  => [$self->{Y}, $self->{X}],
    rank  => "highest",
    score => sub {
      my ($y, $x) = @_;
      # If $ohno has moved, then we can backtrack -- that's often to our benefit.
      return if !$moved and $self->{LastMv} and $y == $self->{LastMv}[0] and $x == $self->{LastMv}[1];
      return euclid($ohno->{Y}, $ohno->{X}, $y, $x)
    }
  );
  $self->{LastFleeFrom} = [$ohno->{Y}, $ohno->{X}];
  $self->go(@go) if @go;

  return 0.3;
}

42;
