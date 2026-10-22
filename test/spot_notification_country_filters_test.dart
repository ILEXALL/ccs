import 'package:flutter_test/flutter_test.dart';
import 'package:ccs_app/features/spots/data/spot_filters.dart';

void main() {
  test('default countries contain only the registered country', () {
    final selected = spotCountryFiltersFromUserData({'country': 'Latvia'});
    expect(selected, {'Latvia'});
    expect(userDataAllowsSpotCountry({'country': 'Latvia'}, 'LV'), isTrue);
    expect(userDataAllowsSpotCountry({'country': 'Latvia'}, 'RU'), isFalse);
  });
  test('checked countries control notifications, including moderators', () {
    final user = {
      'country': 'Latvia',
      'spotCountryFilters': ['RU'],
      'role': 'moderator',
      'moderatorCountryCodes': ['LV'],
    };
    expect(userDataAllowsSpotCountry(user, 'RU'), isTrue);
    expect(userDataAllowsSpotCountry(user, 'LV'), isFalse);
    expect(userDataAllowsSpotCountry({}, 'LV'), isFalse);
  });
}
