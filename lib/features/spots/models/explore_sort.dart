enum ExploreSortMode { popular, newest, nearest, meet }

String exploreSortLabel(ExploreSortMode mode) {
  switch (mode) {
    case ExploreSortMode.popular:
      return 'Popular';
    case ExploreSortMode.newest:
      return 'Newest';
    case ExploreSortMode.nearest:
      return 'Nearest';
    case ExploreSortMode.meet:
      return 'Meet';
  }
}

const upcomingEventsCategoryName = 'Upcoming';
