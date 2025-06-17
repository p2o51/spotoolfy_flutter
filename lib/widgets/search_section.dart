import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/search_provider.dart';
import '../widgets/library_grid.dart';
import '../widgets/materialui.dart' as custom_ui;
import '../l10n/app_localizations.dart';

class SearchSection extends StatefulWidget {
  final VoidCallback onBackPressed;
  
  const SearchSection({
    Key? key,
    required this.onBackPressed,
  }) : super(key: key);

  @override
  State<SearchSection> createState() => _SearchSectionState();
}

class _SearchSectionState extends State<SearchSection> {
  @override
  void initState() {
    super.initState();
  }
  
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchProvider>(
      builder: (context, searchProvider, child) {
        final screenWidth = MediaQuery.of(context).size.width;
        final gridCrossAxisCount = switch (screenWidth) {
          > 900 => 6,
          > 600 => 5,
          _ => 3,
        };
        
        return Column(
          children: [
            // Search results header with back button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBackPressed,
                    tooltip: AppLocalizations.of(context)!.backToLibraryTooltip,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Center(
                      child: custom_ui.IconHeader(
                        icon: Icons.search,
                        text: AppLocalizations.of(context)!.searchResults,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), 
                ],
              ),
            ),
            
            // Loading indicator
            if (searchProvider.isSearching)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(),
              ),
              
            // Error message  
            if (searchProvider.errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  searchProvider.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              
            // Search results using CustomScrollView for potential future sliver integration
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (searchProvider.filteredResults.isEmpty && !searchProvider.isSearching)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyResultsView(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: LibraryGrid(
                        items: searchProvider.filteredResults,
                        gridCrossAxisCount: gridCrossAxisCount,
                        onItemTap: (item) => searchProvider.playItem(item),
                      ),
                    )
                ],
              )
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildEmptyResultsView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noResultsFound,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.tryDifferentKeywords,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 