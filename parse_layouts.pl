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

my @colorTab = ('#00007F', '#007F00', '#7F0000');


my $data;
{
  local $/ = undef;
  $data = <DATA>;
}

my $path = $layoutSource; $path =~ s/\/[a-zA-Z0-9_.-]+\.c$//;
$path = "$path/layers";
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

foreach my $layerNb(sort keys %{$layout}) {
  my $l = $layout->{$layerNb}->{'name'};

  # import ergodox svg
  my $svg = parseSVG(
      SVG::Parser->new()->parse($data),
      $layout->{$layerNb}->{'keys'} );

  my $text = $svg->text(x => 410, y => 50,
      fill  => '#000000', 'font-size' => 25,
  )->cdata($l);

  my $f = "$path/$layerNb.$l";
  exportPNG($svg, $f) if $export eq 'export';
  open(FH, '>:utf8',"$f.svg") or die("Problem opening $f.svg");
  print FH $svg->xmlify();
  close FH;
}


# we want some layers on one svg
if ((keys %groupLayers) >= 1) {
  my $color = '#000';
  my $allkeys_svg = SVG::Parser->new()->parse($data);

  my $offset = 8;
  my $count = 1;
  foreach my $layerNb(sort keys %{$layout}) {
    my $l = $layout->{$layerNb}->{'name'};

    if (defined($groupLayers{uc $l})) {
      # print a key for each rect in svg
      ELEM:foreach my $g($allkeys_svg->getElements('rect')) {
        my $knb = $g->getAttribute('data-key');
        my $x = $g->getAttribute('x') + 2;
        my $y = $g->getAttribute('y') + ($offset*($count));
        my $key = $layout->{$layerNb}->{'keys'}->[$knb-1];
        next ELEM if ($key eq 'TRANSPARENT');

        $g->setAttribute("stroke", "#444");
        $g->setAttribute("fill", "#fff");

        my $parent = $g->getParentElement();
        my $text = $parent->text(x => $x, y => $y, fill => $color, 'font-size' => $offset, )->cdata($key);
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
    }
    # remove attribute for rasterize
    $g->setAttribute('data-key', undef);
  }

  return $svg;
}



__DATA__
<?xml version="1.0" encoding="UTF-8" standalone="no"?>

<svg class="layer layer-template" width="1000px" height="375px" viewBox="0 0 1000 375" version="1.1"
     xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <g transform="translate(500.000000, 0.000000)">
    <rect class="left keykey-70" data-key="70" x="425" y="220" width="50" height="50"></rect>
    <rect class="left keykey-65" data-key="65" x="425" y="168" width="75" height="50"></rect>
    <rect class="left keykey-58" data-key="58" x="425" y="116" width="75" height="50"></rect>
    <rect class="left keykey-52" data-key="52" x="425" y="64" width="75" height="50"></rect>
    <rect class="left keykey-45" data-key="45" x="425" y="12" width="75" height="50"></rect>
    <rect class="left keykey-69" data-key="69" x="373" y="220" width="50" height="50"></rect>
    <rect class="left keykey-64" data-key="64" x="373" y="168" width="50" height="50"></rect>
    <rect class="left keykey-57" data-key="57" x="373" y="116" width="50" height="50"></rect>
    <rect class="left keykey-51" data-key="51" x="373" y="64" width="50" height="50"></rect>
    <rect class="left keykey-44" data-key="44" x="373" y="12" width="50" height="50"></rect>
    <rect class="left keykey-68" data-key="68" x="321" y="212" width="50" height="50"></rect>
    <rect class="left keykey-63" data-key="63" x="321" y="160" width="50" height="50"></rect>
    <rect class="left keykey-56" data-key="56" x="321" y="108" width="50" height="50"></rect>
    <rect class="left keykey-50" data-key="50" x="321" y="56" width="50" height="50"></rect>
    <rect class="left keykey-43" data-key="43" x="321" y="4" width="50" height="50"></rect>
    <rect class="left keykey-67" data-key="67" x="269" y="208" width="50" height="50"></rect>
    <rect class="left keykey-62" data-key="62" x="269" y="156" width="50" height="50"></rect>
    <rect class="left keykey-55" data-key="55" x="269" y="104" width="50" height="50"></rect>
    <rect class="left keykey-49" data-key="49" x="269" y="52" width="50" height="50"></rect>
    <rect class="left keykey-42" data-key="42" x="269" y="0" width="50" height="50"></rect>
    <rect class="left keykey-66" data-key="66" x="217" y="212" width="50" height="50"></rect>
    <rect class="left keykey-61" data-key="61" x="217" y="160" width="50" height="50"></rect>
    <rect class="left keykey-54" data-key="54" x="217" y="108" width="50" height="50"></rect>
    <rect class="left keykey-48" data-key="48" x="217" y="56" width="50" height="50"></rect>
    <rect class="left keykey-41" data-key="41" x="217" y="4" width="50" height="50"></rect>
    <rect class="left keykey-60" data-key="60" x="165" y="164" width="50" height="50"></rect>
    <rect class="left keykey-53" data-key="53" x="165" y="112" width="50" height="50"></rect>
    <rect class="left keykey-47" data-key="47" x="165" y="60" width="50" height="50"></rect>
    <rect class="left keykey-40" data-key="40" x="165" y="8" width="50" height="50"></rect>
    <rect class="left keykey-59" data-key="59" x="113" y="139" width="50" height="75"></rect>
    <rect class="left keykey-46" data-key="46" x="113" y="61" width="50" height="75"></rect>
    <rect class="left keykey-39" data-key="39" x="113" y="8" width="50" height="50"></rect>
    <g transform="translate(103.546846, 271.000000) rotate(-25.000000) translate(-103.546846, -271.000000) translate(26.046846, 194.000000)">
      <rect class="left keykey-75" data-key="75" x="53" y="53" width="50" height="100"></rect>
      <rect class="left keykey-72" data-key="72" x="53" y="5.68434189e-14" width="50" height="50"></rect>
      <rect class="left keykey-76" data-key="76" x="105" y="53" width="50" height="100"></rect>
      <rect class="left keykey-74" data-key="74" x="1" y="104" width="50" height="50"></rect>
      <rect class="left keykey-73" data-key="73" x="1" y="52" width="50" height="50"></rect>
      <rect class="left keykey-71" data-key="71" x="1" y="5.68434189e-14" width="50" height="50"></rect>
    </g>
  </g>
  <g>
    <rect class="right keykey-27" data-key="27" x="337" y="139" width="50" height="75"></rect>
    <rect class="right keykey-14" data-key="14" x="337" y="61" width="50" height="75"></rect>
    <rect class="right keykey-7" data-key="7" x="337" y="8" width="50" height="50"></rect>
    <rect class="right keykey-26" data-key="26" x="285" y="164" width="50" height="50"></rect>
    <rect class="right keykey-20" data-key="20" x="285" y="112" width="50" height="50"></rect>
    <rect class="right keykey-13" data-key="13" x="285" y="60" width="50" height="50"></rect>
    <rect class="right keykey-6" data-key="6" x="285" y="8" width="50" height="50"></rect>
    <rect class="right keykey-32" data-key="32" x="233" y="212" width="50" height="50"></rect>
    <rect class="right keykey-25" data-key="25" x="233" y="160" width="50" height="50"></rect>
    <rect class="right keykey-19" data-key="19" x="233" y="108" width="50" height="50"></rect>
    <rect class="right keykey-12" data-key="12" x="233" y="56" width="50" height="50"></rect>
    <rect class="right keykey-5" data-key="5" x="233" y="4" width="50" height="50"></rect>
    <rect class="right keykey-31" data-key="31" x="181" y="208" width="50" height="50"></rect>
    <rect class="right keykey-24" data-key="24" x="181" y="156" width="50" height="50"></rect>
    <rect class="right keykey-18" data-key="18" x="181" y="104" width="50" height="50"></rect>
    <rect class="right keykey-11" data-key="11" x="181" y="52" width="50" height="50"></rect>
    <rect class="right keykey-4" data-key="4" x="181" y="0" width="50" height="50"></rect>
    <rect class="right keykey-30" data-key="30" x="129" y="212" width="50" height="50"></rect>
    <rect class="right keykey-23" data-key="23" x="129" y="160" width="50" height="50"></rect>
    <rect class="right keykey-17" data-key="17" x="129" y="108" width="50" height="50"></rect>
    <rect class="right keykey-10" data-key="10" x="129" y="56" width="50" height="50"></rect>
    <rect class="right keykey-3" data-key="3" x="129" y="4" width="50" height="50"></rect>
    <rect class="right keykey-29" data-key="29" x="77" y="220" width="50" height="50"></rect>
    <rect class="right keykey-22" data-key="22" x="77" y="168" width="50" height="50"></rect>
    <rect class="right keykey-16" data-key="16" x="77" y="116" width="50" height="50"></rect>
    <rect class="right keykey-9" data-key="9" x="77" y="64" width="50" height="50"></rect>
    <rect class="right keykey-2" data-key="2" x="77" y="12" width="50" height="50"></rect>
    <rect class="right keykey-28" data-key="28" x="25" y="220" width="50" height="50"></rect>
    <rect class="right keykey-21" data-key="21" x="0" y="168" width="75" height="50"></rect>
    <rect class="right keykey-15" data-key="15" x="0" y="116" width="75" height="50"></rect>
    <rect class="right keykey-8" data-key="8" x="0" y="64" width="75" height="50"></rect>
    <rect class="right keykey-1" data-key="1" x="0" y="12" width="75" height="50"></rect>
    <g transform="translate(397.733614, 271.211309) rotate(25.000000) translate(-397.733614, -271.211309) translate(320.233614, 193.711309)">
      <rect class="right keykey-37" data-key="37" x="52" y="53" width="50" height="100"></rect>
      <rect class="right keykey-36" data-key="36" x="5.68434189e-14" y="53" width="50" height="100"></rect>
      <rect class="right keykey-38" data-key="38" x="104" y="104" width="50" height="50"></rect>
      <rect class="right keykey-35" data-key="35" x="104" y="52" width="50" height="50"></rect>
      <rect class="right keykey-34" data-key="34" x="104" y="0" width="50" height="50"></rect>
      <rect class="right keykey-33" data-key="33" x="52" y="2.84217094e-14" width="50" height="50"></rect>
    </g>
  </g>
</svg>
