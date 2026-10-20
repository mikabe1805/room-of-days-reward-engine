/// The six life stats. The code names are older than the names the app
/// shows: str is Body, vit is Care, intl is Mind, foc is Craft, soc is
/// People and dis is Home. In the app each stat also carries a color and a
/// short description; this sample keeps only the names.
enum Stat {
  str('BODY', 'Body'),
  vit('CARE', 'Care'),
  intl('MIND', 'Mind'),
  foc('CRAFT', 'Craft'),
  soc('PEOPLE', 'People'),
  dis('HOME', 'Home');

  const Stat(this.abbr, this.label);
  final String abbr;
  final String label;
}
