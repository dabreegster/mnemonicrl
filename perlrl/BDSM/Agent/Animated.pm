package BDSM::Agent::Animated;

use strict;
use warnings;
use Util;

use base "BDSM::Agent::Sprite";
__PACKAGE__->announce("Animated");

# Loops through frames, this sprite does
sub new {
  my ($class, %opts) = @_;

  # Transform our animation into a shape list first
  my $cnt = 0;
  my %frames;
  my @lines = slurp($opts{File});

  # TODO: messy
  my $height = 0;
  my $width = length($lines[0]);

  while (@lines) {
    my $frame = "";
    while ((my $line = shift(@lines)) ne "-NEXTFRAME-") {
      $height++ unless $cnt;
      $frame .= "$line\n";
    }
    $frames{$cnt++} = $frame;
  }

  $opts{Shapes} = \%frames;
  $opts{Shape} ||= 0;

  my $self = $class->SUPER::new(
    %opts,
    FloatingBlit => 1,
    EarlyConstruct => ["File"]  # so our ID prettyprints
  );
  $self->_construct(\%opts => "Delay", "Cycle", "Tags");
  $self->{Tags} or die "animated needs tag list\n";
  $self->{Cycle} ||= "forward";

  $self->{Frames} = $cnt - 1;

  if ($self->void) {
    debug "animated couldnt go, so not setting rectangle";
  } else {
    $self->{Y1} = $self->{Y};
    $self->{X1} = $self->{X};
    $self->{Y2} = $self->{Y} + $height;
    $self->{X2} = $self->{X} + $width;
    $self->{Map}{Rectangles}{ "anim_$self->{ID}" } = $self; # where do you go?
  }

  return $self;
}

# TODO meh, ill leave these here, animateds are all View anyway.
sub on_screen {
  my $self = shift;
  $self->schedule(
    -do => "cycleframe", -tags => $self->{Tags}, -id => "animated_$self->{ID}"
  );
}

sub off_screen {
  my $self = shift;
  GAME->unschedule(-actor => $self);
}

sub cycleframe {
  my $self = shift;
  return if $self->void;  # Don't animate outside of a map

  my $next;
  if ($self->{Cycle} eq "reverse") {
    $next = $self->{CurShape} - 1;
    $next = $self->{Frames} if $next < 0;
  } else {
    $next = $self->{CurShape} + 1;
    $next = 0 if $next > $self->{Frames};
  }
  $self->transform($next);

  return $self->{Delay};
}

sub id {
  my $self = shift;
  return $self->type . "_$self->{ID}_$self->{File}";
}

42;
