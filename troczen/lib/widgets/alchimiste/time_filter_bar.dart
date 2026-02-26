import 'package:flutter/material.dart';

enum TimeFilter {
  days7('7j'),
  days30('30j'),
  quarter('Trimestre'),
  custom('Personnalisé');

  final String label;
  const TimeFilter(this.label);
}

class TimeFilterBar extends StatelessWidget {
  final TimeFilter selectedFilter;
  final ValueChanged<TimeFilter> onFilterChanged;
  final DateTimeRange? customDateRange;
  final ValueChanged<DateTimeRange?> onCustomDateRangeChanged;

  const TimeFilterBar({
    super.key,
    required this.selectedFilter,
    required this.onFilterChanged,
    this.customDateRange,
    required this.onCustomDateRangeChanged,
  });

  Future<void> _selectCustomDateRange(BuildContext context) async {
    final initialDateRange = customDateRange ??
        DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 7)),
          end: DateTime.now(),
        );

    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: initialDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFFB347),
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedRange != null) {
      onCustomDateRangeChanged(pickedRange);
      onFilterChanged(TimeFilter.custom);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        border: Border(
          bottom: BorderSide(color: Colors.white12, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: TimeFilter.values.map((filter) {
            final isSelected = selectedFilter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(
                  filter == TimeFilter.custom && customDateRange != null && isSelected
                      ? '${customDateRange!.start.day}/${customDateRange!.start.month} - ${customDateRange!.end.day}/${customDateRange!.end.month}'
                      : filter.label,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    if (filter == TimeFilter.custom) {
                      _selectCustomDateRange(context);
                    } else {
                      onFilterChanged(filter);
                    }
                  }
                },
                selectedColor: const Color(0xFFFFB347),
                backgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFFFFB347) : Colors.white24,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
