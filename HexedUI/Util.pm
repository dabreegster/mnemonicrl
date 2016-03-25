package HexedUI::Util;

use strict;
use warnings;

use parent "Exporter";

use PUtil::Include;
our @EXPORT = (@PUtil::Include::EXPORT, @Curses::EXPORT,
               qw(longest wrap cleanlines paint));

use Curses;
use Memoize;

# Return the length of the longest member, with regards to color tag
sub longest {
  my $len = 0;
  foreach (@_) {
    my $copy = $_;
    $copy =~ s/<(\w+)>//g;
    $len = length($copy) if length($copy) > $len;
  }
  return $len;
}

# The eternal word wrap routine from my first programming days needed a rehaul. This splits
# lines up based on the width but doesn't count <color> tags.
sub wrap {
  my ($width, $in) = @_;

  my @lines;
  my $line = "";
  my $realline = "";
  foreach my $realword (split(/ /, $in)) {
    my $word = $realword;
    $word =~ s/<[^>]+>//g;

    if ($line) {
      if (length($line) + length($word) + 1 <= $width) {
        $realline .= " $realword";
        $line .= " $word";
        next;
      } else {
        push @lines, $realline;
        $realline = "";
        $line = "";
      }
    }
    if (length($word) <= $width) {
      $realline = $realword;
      $line = $word;
      next;
    } else {
      # Chop up the word. But first take out the tags and store where they are.
      my @tags;

      my $offset = 0;
      while ($realword =~ m/(<[^>]+>)/g) {
        my $tag = $1;
        my $pos = pos($realword) - length($tag);
        $realword =~ s/<[^>]+>//;
        push @tags, [$tag, $pos + $offset];
        $offset += length($tag);
      }

      # Split $word into substrings by the width
      my $choppos = 0;
      my @split = split(/(.{$width})/, $word);
      foreach (0 .. $#split) {
        my $chunk = $split[$_];
        next unless $chunk;
        $choppos += $width;
        # Do we have any color tags to splice back in?
        while (@tags and $tags[0]->[1] < $choppos) {
          my $splicein = shift @tags;
          substr($chunk, $splicein->[1] - $choppos, 0, $splicein->[0]);
          $choppos += length($splicein->[0]);
        }
        if ($_ == $#split) {
          $realline = $chunk;
          $chunk =~ s/<[^>]+>//;
          $line = $chunk;
        } else {
          push @lines, $chunk;
        }
      }
      next;
    }
  }
  push @lines, $realline;

  return @lines;
}

# my editing style in vim
sub cleanlines {
  foreach (@_) {
    s/\n//g;
    s/\s+/ /g;
  }
}

# Caching color codes is highly useful in big maps. Believe me.
memoize("paint");

# Returns the attribute for the specified color.
sub paint {
  my ($fg, $bg);
  if (@_ == 1) {
    ($fg, $bg) = ($_[0]) ? (split("/", shift)) : ("grey", "black");
  } else {
    ($fg, $bg) = @_;
  }
  # If the foreground and background color are the same, something screws up.
  # So prevent that.
  $bg ||= "black";
  $fg = "black" if $bg =~ m/^(grey|gray|white)$/i and $fg =~ m/^(grey|gray|white)$/i;
  return _trans_color($fg, $bg);
}

# Ask Curses for actual low-level color value.
sub _trans_color {
  my ($fg, $bg) = @_;
  my $bright = 0;
  my %colors = (
    blue   => 5,
    red    => 2,
    green  => 3,
    aqua   => 7,
    cyan   => 7,
    purple => 6,
    orange => 4,
    yellow => 4,
    black  => 1,
    grey   => 8,
    gray   => 8,
    white  => 8
  );
  my $color = $colors{lc $fg};

  # Now we determine whether we're bright or dim.
  # If our first letter is capitalized, we're bright.
  $bright = 1 if substr($fg, 0, 1) eq uc substr($fg, 0, 1);
  # But then we have all these special cases. Simplify fg.
  $fg = lc $fg;
  $bright = 0 if $fg eq "orange";
  $bright = 1 if $fg eq "yellow";
  $bright = 0 if $fg eq "grey" or $fg eq "gray";
  $bright = 1 if $fg eq "white";

  my $attrib = $bright ? A_BOLD() : A_NORMAL();

	# Don't forget background color. >_<
  # TODO special case, make sure this looks the same on all terminals!
  if ($bg eq "faded") {
    $attrib = $attrib ? $attrib | A_BLINK : A_BLINK;
  } else {
    $color += 8 * ($colors{lc $bg} - 1);
  }

  return $attrib | COLOR_PAIR($color);
}

42;
