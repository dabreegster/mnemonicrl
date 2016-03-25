package BDSM::DunGen::Shape;

use strict;
use warnings;
use Util;

use BDSM::Vector;

# We provide common methods for all Shapes. We're just a Map though.
use BDSM::Map;
our @ISA = ("BDSM::Map");

# Scans a shape and records coordinates for connectable walls.
sub findwalls {
  my ($self, $ncut, $scut, $wcut, $ecut) = @_;
  $self->{Exits} = {};
  $self->_walltrace("north", [ 0 .. $ncut ]);
  $self->_walltrace("south", [ $self->height - $scut .. $self->height ]);
  $self->_walltrace("west", [ 0 .. $wcut] );
  $self->_walltrace("east", [ $self->width - $ecut .. $self->width] );
}

# Scans a side of a shape for walls. Should only be called by findwalls, really.
sub _walltrace {
  # Here be meta-programming dragons...
  my ($self, $dir, $loop) = @_;

  # No clue what this stuff does. It's all magic and can do either y or x scans so yeah
  # good luck understanding it.
  my ($measure, $limit, $y, $x, $BIG, $SMALL);
  if (dir_vert($dir)) {
    $measure = "width";
    $limit = $dir eq "north" ? 0 : $self->height;
    ($y, $x) = ("big", "small");
    $BIG = "Y";
    $SMALL = "X";
  } else {
    $measure = "height";
    $limit = $dir eq "west" ? 0 : $self->width;
    ($x, $y) = ("big", "small");
    $BIG = "X";
    $SMALL = "Y";
  }
  my $dat = {};

  # Go through every row or column specified.
  foreach my $big (@$loop) {
    $dat->{big} = $big;
    my $cnt = 0;                # How long is the wall so far?
    my ($start, $end) = (0, 0); # Where does the wall start and end?
    my $mode = 0;               # == 1 if we have a wall right now
    # Go through the row or column.
    foreach my $small (0 .. $self->$measure) {
      $dat->{small} = $small;
      # Are we at a wall?
      if ($self->{Map}[ $dat->{$y} ][ $dat->{$x} ]{_} eq "#") {
        # Wall requirements below. Are we in a bad spot, basically?
        my ($Y, $X) = dir_relative($dir, $dat->{$y}, $dat->{$x});
        next if $big != $limit and $self->{Map}[$Y][$X]{_} ne " ";
        $start = $small if $mode == 0;  # Is this our first tile?
        $mode = 1;  # Inevitably
        $end = $small;
        $cnt++;
      } elsif ($mode == 1) {  # We might have a chance!
        push @{ $self->{Exits}{$dir} }, {
          "${BIG}1" => $big,
          "${BIG}2" => $big,
          "${SMALL}1" => $start,
          "${SMALL}2" => $end,
        } if $cnt >= 3;
        $cnt = $mode = $start = $end = 0;   # Clear things.
      }
    }
    # There might be a wall at the very end we didn't add yet.
    push @{ $self->{Exits}{$dir} }, {
      "${BIG}1" => $big,
      "${BIG}2" => $big,
      "${SMALL}1" => $start,
      "${SMALL}2" => $end,
    } if $cnt >= 3;
  }
}

# A testing routine to make sure the correct walls were marked.
sub _checkwalls {
  my $self = shift;
  foreach my $dir ("north", "south", "west", "east") {
    print STDERR "\n$dir walls:\n";
    foreach my $wall (@{ $self->{Exits}{$dir} }) {
      $self->{Map}[ $wall->{Y1} ][ $wall->{X1} ]{_} = "<";
      $self->{Map}[ $wall->{Y2} ][ $wall->{X2} ]{_} = ">";
      $self->_dump;
      $self->{Map}[ $wall->{Y1} ][ $wall->{X1} ]{_} = "#";
      $self->{Map}[ $wall->{Y2} ][ $wall->{X2} ]{_} = "#";
    }
  }
}

# Blit onto a map if we are able. (Funny how this is Sprite code almost verbatim)
sub place {
  my ($shape, %opts) = @_;
  my $map = $opts{on};
  my ($offy, $offx) = @{ $opts{at} };

  # No hope?
  return if $shape->height + $offy > $map->height or $offy < 0;
  return if $shape->width + $offx > $map->width or $offx < 0;

  # Pre-blit: Will we overlap anything nasty?
  foreach my $y (0 .. $shape->height) {
    last if $opts{forceblit} or $opts{mergeblit};
    foreach my $x (0 .. $shape->width) {
      return unless $map->{Map}[$offy + $y][$offx + $x]{_} eq " ";
    }
  }

  # forceblit = blindly overwrite anything, mergeblit = place as much as possible, nothing
  # means it's gotta be totally clear

  # Blit: Merge the shape onto the map
  foreach my $y (0 .. $shape->height) {
    foreach my $x (0 .. $shape->width) {
      my $tile = $map->{Map}[$offy + $y][$offx + $x];
      $tile->{Layers} //= [];
      next unless $opts{forceblit} or ($tile->{_} eq " " and !@{ $tile->{Layers} });
      %$tile = %{ $shape->copy($y, $x) };
      $tile->{ID} = $#{ $map->{Shapes} } + 1;
    }
  }

  # Translate data too
  foreach my $dir ("north", "south", "west", "east") {
    foreach my $wall (@{ $shape->{Exits}{$dir} }) {
      $wall->{Y1} += $offy;
      $wall->{X1} += $offx;
      $wall->{Y2} += $offy;
      $wall->{X2} += $offx;
    }
  }
  $shape->{ID} = $#{ $map->{Shapes} } + 1;
  push @{ $map->{Shapes} }, $shape;
  return 1;
}

# Blit a shape onto the map connecting to an existing shape.
sub jigsaw {
  # We can be a bit confusing. We connect two shapes on a map. The one already
  # there on the map is ID 'to'. We're branching off of the wall in direction
  # 'dir' of number 'to_wall'. The new shape's opposite wall number 'from_wall'
  # is connected. Got it?
  my ($new, %args) = @_;
  my $map = $args{on};
  my $dir = $args{dir};
  my $align = $args{align};
  my $data = $map->{Shapes}[ $args{to} ]{Exits}{$dir}[ $args{to_wall} ];
  my $newdata = $new->{Exits}{ opposite_dir($dir) }[ $args{from_wall} ];

  my ($y, $x, $skip);
  # We just place, actually. The offsets are fun.
  if ($dir eq "north") {
    $y = $data->{Y1} - $newdata->{Y1} - 1;
    $x = $data->{X1} - $newdata->{X1};
    $skip = ($data->{X2} - $data->{X1}) - ($newdata->{X2} - $newdata->{X1});
    $x += random($skip) if $align eq "middle";
    $x += $skip if $align eq "end";
  } elsif ($dir eq "south") {
    $y = $data->{Y1} + 1 - $newdata->{Y1};
    $x = $data->{X1} - $newdata->{X1};
    $skip = ($data->{X2} - $data->{X1}) - ($newdata->{X2} - $newdata->{X1});
    $x += random($skip) if $align eq "middle";                    
    $x += $skip if $align eq "end";
  } elsif ($dir eq "west") {
    $y = $data->{Y1} - $newdata->{Y1};
    $x = $data->{X1} - $newdata->{X1} - 1;
    $skip = ($data->{Y2} - $data->{Y1}) - ($newdata->{Y2} - $newdata->{Y1});
    $y += random($skip) if $align eq "middle";
    $y += $skip if $align eq "end";
  } elsif ($dir eq "east") {
    $y = $data->{Y1} - $newdata->{Y1};
    $x = $data->{X1} + 1 - $newdata->{X1};
    $skip = ($data->{Y2} - $data->{Y1}) - ($newdata->{Y2} - $newdata->{Y1});
    $y += random($skip) if $align eq "middle";
    $y += $skip if $align eq "end";
  }

  return unless place($new, on => $map, at => [$y, $x]);
  # Let there be a clear path between the shapes.
  _clearout(
    on      => $map,
    between => [ 
                 [$args{to}, $args{to_wall}],
                 [$#{ $map->{Shapes} }, $args{from_wall}]
               ],
    dir     => $dir
  );
  return 1;
}

# Take down the walls between two adjoined shapes.
# We're a method of two shapes at once... don't call us as an object. Messy, I know.
sub _clearout {
  my %data = @_;
  my $map = $data{on};
  my $dir = $data{dir};
  my $shapes = $data{between};
  my $data = $map->{Shapes}[ $shapes->[0][0] ]{Exits}{$dir}[ $shapes->[0][1] ];
  my $newdata = $map->{Shapes}[ $shapes->[1][0] ]{Exits}{ opposite_dir($dir) }[ $shapes->[1][1] ];
  
  my $small = dir_vert($dir) ? "X" : "Y";
  
  my $new = (
             $newdata->{ "${small}2" } - $newdata->{ "${small}1" }
            <
             $data->{ "${small}2" } - $data->{ "${small}1" }
            );
  my $old = !$new;
  
  my %dat = ($new) ? %$newdata : %$data;
  my ($y1, $x1, $y2, $x2);
  ($y1, $x1, $y2, $x2) = @dat{"Y1", "X1", "Y1", "X2"} if dir_vert($dir);
  ($y1, $x1, $y2, $x2) = @dat{"Y1", "X1", "Y2", "X1"} if dir_horiz($dir);
  
  $dir = opposite_dir($dir) if $new;
  
  # Tough to refactor this. :(
  $y1--, $x1++, $x2-- if $dir eq "north";
  $x1++, $y2++, $x2-- if $dir eq "south";                                     
  $y1++, $x1--, $y2-- if $dir eq "west";
  $y1++, $y2--, $x2++ if $dir eq "east";

  $map->fill([ $y1, $x1 ], [ $y2, $x2 ], ".");
}

# Pick a random point on a wall.
sub spawnwall {
  my ($shape, $dir, $map) = @_;
  my $wall = $shape->{Exits}{$dir}[0];  # We're used for halls, which have 1 exit per side.
  my ($y, $x);
  if (dir_vert($dir)) {
    $y = $wall->{Y1};
    $x = random($wall->{X1} + 1, $wall->{X2} - 1);
  } else {
    $y = random($wall->{Y1} + 1, $wall->{Y2} - 1);
    $x = $wall->{X1};
  }

  # With the wall coordinates chosen, see if the tile right off it is valid.
  ($y, $x) = dir_relative($dir, $y, $x);
  if ($y <= 0 or $y >= $map->height or $x <= 0 or $x >= $map->width) {    
    return;
  }
  return ($y, $x);
}

42;
