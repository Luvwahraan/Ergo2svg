#!/usr/bin/env perl

use strict;
use warnings;
use SVG::Parser qw(SAX=XML::LibXML::Parser::SAX Expat SAX);
use SVG::Rasterize;

use utf8;

my %groupLayers;

my $layoutSource  = shift @ARGV;
my $export        = shift @ARGV || 'export'; $export = lc $export;
foreach my $l(@ARGV) {
  $groupLayers{uc $l} = uc $l;
}

my @colorTab = qw/#00007F #007F00 #7F0000/;

my $path = $layoutSource; $path =~ s/\/[a-zA-Z0-9_.-]+\.c$//;
$path = "$path/layers";
print "$path\n";
if ( ! -d "$path" ) {
  mkdir "$path" or die("Problem creating $path\n");
}

sub exportPNG;
sub parseSVG;

# Bépo keycodes from /quantum/keymap_extras/keymap_bepo.h by Didier Loiseau.
my $kcTrad = {
  'REGISTERED_TRADEMARK' => '®',
  'TYPOGRAPHICAL_APOSTROPHE' => '’',
  'DEAD_TILDE' => '~',         'COPYRIGHT' => '©',
  'DOLLAR' => '$',             'DOUBLE_QUOTE' => '"',
  'LEFT_GUILLEMET' => '«',     'RIGHT_GUILLEMET' => '»',
  'LEFT_PAREN' => '(',         'RIGHT_PAREN' => ')',
  'AT' => '@',                 'PLUS' => '+',
  'MINUS' => '-',              'SLASH' => '/',
  'ASTERISK' => '*',           'EQUAL' => '=',
  'PERCENT' => '%',            'E_ACUTE' => 'É',
  'E_GRAVE' => 'È',            'DEAD_CIRCUMFLEX' => '^',
  'COMMA' => ',',              'C_CEDILLA' => 'Ç',
  'E_CIRCUMFLEX' => 'Ê',       'A_GRAVE' => 'À',
  'DOT' => '.',                'APOS' => '\'',
  'HASH' => '#',               'DEGREE' => '°',
  'GRAVE' => '`',              'EXCLAIM' => '!',
  'SCOLON' => ';',             'COLON' => ':',
  'QUESTION' => '?',           'EN_DASH' => '–',
  'EM_DASH' => '—',            'LESS' => '<',
  'GREATER' => '>',            'LBRACKET' => '[',
  'RBRACKET' => ']',           'CIRCUMFLEX' => '^',
  'PLUS_MINUS' => '±',         'MATH_MINUS' => '−',
  'OBELUS' => '÷',             'TIMES' => '×',
  'DIFFERENT' => '≠',          'PERMILLE' => '‰',
  'PIPE' => '|',               'DEAD_ACUTE' => '´',
  'AMPERSAND' => '&',          'OE_LIGATURE' => 'Œ',
  'DEAD_GRAVE' => '`',         'INVERTED_EXCLAIM' => '¡',
  'DEAD_CARON' => 'ˇ',         'ETH' => 'ð',
  'DEAD_SLASH' => '/',         'IJ_LIGATURE' => 'ĳ',
  'SCHWA' => 'ə',              'DEAD_BREVE' => '˘',
  'AE_LIGATURE' => 'Æ',        'U_GRAVE' => 'Ù',
  'DEAD_TREMA' => '¨',         'EURO' => '€',
  'THORN' => 'þ',              'SHARP_S' => 'ß',
  'DEAD_MACRON' => '¯',        'DEAD_CEDILLA' => '¸',
  'NONUS_SLASH' => '/',        'LEFT_CURLY_BRACE' => '{',
  'RIGHT_CURLY_BRACE' => '}',  'ELLIPSIS' => '…',
  'TILDE' => '~',              'INVERTED_QUESTION' => '¿',
  'DEAD_RING' => '°',          'DEAD_GREEK' => 'Greek',
  'DAGGER' => '†',             'DEAD_OGONEK' => '˛',
  'UNDERSCORE' => '_',         'PARAGRAPH' => '¶',
  'LOW_DOUBLE_QUOTE' => '„',   'LEFT_DOUBLE_QUOTE' => '“',
  'RIGHT_DOUBLE_QUOTE' => '”', 'LESS_OR_EQUAL' => '≤',
  'GREATER_OR_EQUAL' => '≥',   'NEGATION' => '¬',
  'ONE_QUARTER' => '¼',        'ONE_HALF' => '½',
  'THREE_QUARTERS' => '¾',     'MINUTES' => '′',
  'SECONDS' => '″',            'BROKEN_PIPE' => '¦',
  'DEAD_DOUBLE_ACUTE' => '˝',  'SECTION' => '§',
  'GRAVE_BIS' => '`',          'DEAD_DOT_ABOVE' => '˙',
  'DEAD_CURRENCY' => '¤',      'DEAD_HORN' => '̛',
  'LONG_S' => 'ſ',             'TRADEMARK' => '™',
  'ORDINAL_INDICATOR_O' => 'º','DEAD_COMMA' => '˛',
  'LEFT_QUOTE' => '‘',         'RIGHT_QUOTE' => '’',
  'INTERPUNCT' => '·',         'DEAD_HOOK_ABOVE' => '̉',
  'DEAD_UNDERDOT' => '̣',       'DOUBLE_DAGGER' => '‡',
  'ORDINAL_INDICATOR_A' => 'ª',
  'DOLLAR' => '$',             'DLR' => '$',
  'EGRV' => 'È',               'EACU' => 'É',
  'AGRV' => 'À',               'COMM' => ',',
  'DOT' => '.',                'ECUT' => 'É',
  'LEFT' => '←',               'RIGHT' => '→',
  'UP' => '↑',                 'DOWN' => '↓',

  '_{6,7}' => 'TRANSPARENT',      'X{7}' => 'NO',
};

# parse layouts
my $layout = {};
my $keymaps = 0;
my $newlayout = 0;
my $curLayout = '';
my $layNb = -1;
open(SRC, $layoutSource);
LINE:while (my $line = <SRC>) {
  # simplify line removing multi spaces
  $line =~ s/ +/ /g;
  study $line;

  # layouts def starts here
  if ($line =~ /^const uint16_t PROGMEM keymaps/) {
    $keymaps = 1;
    next LINE;
  }

  # end block or and layouts def
  if ($line =~ / ?}; ?$/) { $keymaps = 0; }
  next LINE unless $keymaps == 1;

  # new layout
  if ($line =~ /^\[([a-zA-Z_0-9]+)\] += +(LAYOUT_ergodox|KEYMAP) ?\(/) {
    $curLayout = $1;
    $layNb++;
    next LINE;
  }

  # clean last layout line
  $line =~ s/(\),)$//;

  # get keycodes from a layout's line
  SPLIT:foreach my $w(split(' ', $line))
  {
    # we don't need last comma
    $w =~ s/,$//;
    study $w;

    # there is no keycode in comments -> next line
    next LINE if ($w =~ m#^(/\*)|( ?\*)|( ?//)#);

    # clean and replace keycodes for readability on final svg
    $w =~ s/^(KC|BP|FR)_//;
    foreach my $p(keys %{$kcTrad}) {
      $w =~ s/^$p$/$kcTrad->{$p}/;
    }

    $layout->{$layNb}->{'name'} = $curLayout;
    push(@{$layout->{$layNb}->{'keys'}}, $w);
  }
}
close SRC;

foreach my $i(sort keys %{$layout}) {
  my $l = $layout->{$i}->{'name'};
  print "Handle $l\n";

  # import ergodox svg
  my $svg = parseSVG(
      SVG::Parser->new()->parsefile('ergodox.svg'),
      $layout->{$i}->{'keys'} );

  my $text = $svg->text(x => 410, y => 50,
      fill  => '#000000', 'font-size' => 25,
  )->cdata($l);

  my $f = "$path/$i.$l";
  exportPNG($svg, $f) if $export eq 'export';
  open(FH, '>:utf8',"$f.svg") or die("Problem opening $f.svg");
  print FH $svg->xmlify();
  close FH;
}


# we want some layers on one svg
if ((keys %groupLayers) >= 1) {
  my $color = '#000';
  my $allkeys_svg = SVG::Parser->new()->parsefile('ergodox.svg');

  my $offset = 8;
  my $count = 1;
  foreach my $i(sort keys %{$layout}) {
    my $l = $layout->{$i}->{'name'};

    if (defined($groupLayers{uc $l})) {
      # print a key for each rect in svg
      print "Handle $l in combined svg\n";
      ELEM:foreach my $g($allkeys_svg->getElements('rect')) {
        my $knb = $g->getAttribute('data-key');
        my $x = $g->getAttribute('x') + 2;
        my $y = $g->getAttribute('y') + ($offset*($count));

        if ($knb == 23) {
          print "Offset: $offset, $count -> ", $offset*($count), "\n";
        }

        my $key = $layout->{$i}->{'keys'}->[$knb-1];
        next ELEM if ($key eq 'TRANSPARENT');

        $g->setAttribute("stroke", "#444");
        $g->setAttribute("fill", "#fff");

        my $parent = $g->getParentElement();
        my $text = $parent->text(x => $x, y => $y, fill => $color, 'font-size' => 8, )->cdata($key);
        $text = $allkeys_svg->text(x => 410, y => 5+25*($count), fill  => $color, 'font-size' => 25, )->cdata($l);
      }
      $color = $colorTab[$count % scalar(@colorTab)];
      $count++;
    }

  }

  # remove attribute for rasterize
  foreach my $g($allkeys_svg->getElements('rect')) {
    $g->setAttribute('data-key', undef);
  }

  my $f = "$path/combined";
  exportPNG($allkeys_svg, $f) if $export eq 'export';
  open(FH, '>:utf8',"$f.svg") or die("Problem opening $f.svg");
  print FH $allkeys_svg->xmlify();
  close FH;
}


sub exportPNG{
  my $svg = shift;
  my $f = shift;
  my $rasterize = SVG::Rasterize->new();
  $rasterize->rasterize(svg => $svg);
  $rasterize->write(type => 'png', file_name => "$f.png");
}


sub parseSVG {
  my ($svg,$keyHashref) = @_;

  my $fontSize = 8;
  # print a key for each rect in svg
  ELEM:foreach my $g($svg->getElements('rect')) {
    my $knb = $g->getAttribute('data-key');
    my $x = $g->getAttribute('x');
    my $y = $g->getAttribute('y');
    my $key = $keyHashref->[$knb-1];

    if ($key eq 'TRANSPARENT') {
      $g->setAttribute("stroke", "#444444");
      $g->setAttribute("fill-opacity", "0");
    } elsif ($key eq 'NO') {
      $g->setAttribute("fill-opacity", "1");
      $g->setAttribute("fill", "#444");
    } else {
      $g->setAttribute("stroke", "#444");
      $g->setAttribute("fill", "#fff");
      my $parent = $g->getParentElement();
      my $text = $parent->text(x => $x+2, y => $y+$fontSize, fill  => '#000',
          'font-size' => $fontSize, )->cdata($key);
      #$g->insertAfter($text);
      #$g->insertSiblingAfter($text);
    }
    # remove attribute for rasterize
    $g->setAttribute('data-key', undef);
  }

  return $svg;
}


__END__
