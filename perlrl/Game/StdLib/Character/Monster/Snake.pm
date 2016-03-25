package Game::StdLib::Character::Monster::Snake;

use strict;
use warnings;
use Util;

use base "Game::StdLib::Character::Monster";
__PACKAGE__->announce("Snake");

use BDSM::Vector;

# TODO This is a great example of a 'behavior'. we're not really Monster-specific; we're
# Agent-specific. but how to OOP that? :)

sub new {
  my ($class, %opts) = @_;
  my $self = $class->SUPER::new(%opts);
  # Two styles... specify a length or a string
  if ($opts{Length}) {
    $self->{Length} = delete $opts{Length};
  } else {
    $self->{Length} = length($opts{String});
    $self->{String} = [split(//, delete $opts{String})];
    $self->{StringAt} = 0;
  }
  $self->_construct(\%opts => "Lookahead");
  $self->{Lookahead} //= 1;
  $self->{Snake} = [];
  return $self;
}

# Snakey effect!
sub AFTER_go {
  my ($self, $heap, $y, $x) = actargs @_;
  return unless $heap->{From};

  # New piece
  my @tail = @{ $heap->{From} };
  my $sym;
  if ($self->{String}) {
    $sym = $self->{String}[ $self->{StringAt}++ ];
    $self->{StringAt} = 0 if $self->{StringAt} > $#{ $self->{String} };
  } else {
    $sym = "!";
  }
  unless ($sym eq " ") {
    $self->{Map}->tile(@tail)->{Actor} = {
      Aggregate => $self,
      Sprite    => $self,
      Symbol    => $sym,
      Color     => $self->Color
    };
    $self->{Map}->modded(@tail);

    # Trimming needed?
    push @{ $self->{Snake} }, \@tail;
    if (@{ $self->{Snake} } > $self->{Length}) {
      my @nuke = @{ shift @{ $self->{Snake} } };
      delete $self->{Map}->tile(@nuke)->{Actor};
      $self->{Map}->modded(@nuke);
    }
  }

  $self->lag(0.1);
  $self->super("AFTER_go", $heap);
}

sub WhenCollide {
  my ($self, $heap, $victim, $toy, $tox) = @_;
  if ($victim->{ID} == $self->{ID}) {
    msg see => "ouch!";
    return STOP;
  } else {
    return $self->super("WhenCollide", $heap, $victim, $toy, $tox);
  }
}

sub AI_turn {
  my $self = shift;

  my @best = $self->{Map}->bestadj(
    from   => [$self->{Y}, $self->{X}],
    diag   => 0,
    actors => 0,
    rank   => "highest",
    score  => sub {
      # Go to a blank tile with the most blank tiles surrounding it.
      # But recursively choose depth of our lookahead
      return _clear($self->{Map}, @$_, $self->{Lookahead});
    }
  );
  if (@best) {
    $self->go(@best);
  } else {
    msg see => "damnit, stuck";
    $self->lag(1);
  }

  return $self->{Lag} // 0.5;
}

# Recursively score a move by how clear it and its surrounding dealies are
sub _clear {
  my ($map, $y, $x, $depth) = @_;
  my $clear = 0;
  foreach (adjacent_tiles("diag", $y, $x)) {
    next unless $map->permeable(@$_); # Is it traversable?
    next if ref $map->get(@$_);       # Is there stuff there?
    if ($depth > 0) {
      $clear += _clear($map, @$_, $depth - 1);
    } else {
      $clear++;
    }
  }
  return $clear;
}

42;
