#ifndef _hldata_h_included_
#define _hldata_h_included_

#include <vector>
#include <string>
#include <set>
#include <map>

/** Store data about user search terms and their expansions. This is used
 * mostly for highlighting result text and walking the matches, generating 
 * spelling suggestions.
 */
struct HighlightData {
    /** The user terms, excluding those with wildcards. This list is
     * intended for orthographic suggestions so the terms are always
     * lowercased, unaccented or not depending on the type of index 
     * (as the spelling dictionary is generated from the index terms).
     */
    std::set<std::string> uterms;

    /** The db query terms linked to the uterms entry they were expanded from. 
     * This is used for aggregating term stats when generating snippets (for 
     * choosing the best terms, allocating slots, etc. )
     */
    std::map<std::string, std::string> terms;

    /** The original user terms-or-groups. This is for display
     * purposes: ie when creating a menu to look for a specific
     * matched group inside a preview window. We want to show the
     * user-entered data in the menu, not some transformation, so
     * these are always raw, diacritics and case preserved.
     */
    std::vector<std::vector<std::string> > ugroups;

    /** Processed/expanded terms and groups. Used for looking for
     * regions to highlight. A group can be a PHRASE or NEAR entry (we
     * process everything as NEAR to keep things reasonably
     * simple. Terms are just groups with 1 entry. All
     * terms are transformed to be compatible with index content
     * (unaccented and lowercased as needed depending on
     * configuration), and the list may include values
     * expanded from the original terms by stem or wildcard expansion.
     */
    std::vector<std::vector<std::string> > groups;
    /** Group slacks. Parallel to groups */
    std::vector<int> slacks;

    /** Index into ugroups for each group. Parallel to groups. As a
     * user term or group may generate many processed/expanded terms
     * or groups, this is how we relate an expansion to its source
     * (used, e.g. for generating anchors for walking search matches
     * in the preview window).
     */
    std::vector<size_t> grpsugidx;

    void clear()
    {
	uterms.clear();
	ugroups.clear();
	groups.clear();
	slacks.clear();
	grpsugidx.clear();
    }
    void append(const HighlightData&);

    // Print (debug)
    void toString(std::string& out) const;
};

inline void setWinMinMax(int pos, int& sta, int& sto)
{
    if (pos < sta) {
        sta = pos;
    }
    if (pos > sto) {
        sto = pos;
    }
}

// Check that at least an entry from the first position list is inside
// the window and recurse on next list. The window is readjusted as
// the successive terms are found. Mostly copied from Xapian code.
//
// @param window the search window width
// @param plists the position list vector
// @param i the position list to process (we then recurse with the next list)
// @param min the current minimum pos for a found term
// @param max the current maximum pos for a found term
// @param sp, ep output: the found area
// @param minpos bottom of search: this is the highest point of
//    any previous match. We don't look below this as overlapping matches 
//    make no sense for highlighting.
extern bool do_proximity_test(
    int window, std::vector<const std::vector<int>*>& plists, 
    unsigned int i, int min, int max, int *sp, int *ep, int minpos);


/**** The following is used by plaintorich.cpp for finding zones to
   highlight and by rclabsfromtext.cpp to choose fragments for the
   abstract */

struct GroupMatchEntry {
    // Start/End byte offsets in the document text
    std::pair<int, int> offs;
    // Index of the search group this comes from: this is to relate a 
    // match to the original user input.
    size_t grpidx;
    GroupMatchEntry(int sta, int sto, size_t idx) 
        : offs(sta, sto), grpidx(idx) {
    }
};

// Find NEAR matches for one group of terms.
//
// @param hldata Data about the user query
// @param grpidx Index in hldata.groups for the group we process
// @param inplists Position lists for the the group terms
// @param gpostobytes Translation of term position to start/end byte offsets
// @param[out] tboffs Found matches
extern bool matchGroup(
    const HighlightData& hldata,
    unsigned int grpidx,
    const std::map<std::string, std::vector<int>>& inplists,
    const std::map<int, std::pair<int,int>>& gpostobytes,
    std::vector<GroupMatchEntry>& tboffs
    );

#endif /* _hldata_h_included_ */
