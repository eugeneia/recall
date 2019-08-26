/* Copyright (C) 2004 J.F.Dockes
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */
#ifndef _DOCSEQDB_H_INCLUDED_
#define _DOCSEQDB_H_INCLUDED_
#include "docseq.h"
#include <memory>

#include "searchdata.h"
#include "rclquery.h"

/** A DocSequence from a Db query */
class DocSequenceDb : public DocSequence {
 public:
    DocSequenceDb(std::shared_ptr<Rcl::Db> db,
                  std::shared_ptr<Rcl::Query> q, const string &t, 
		  std::shared_ptr<Rcl::SearchData> sdata);
    virtual ~DocSequenceDb() {}
    virtual bool getDoc(int num, Rcl::Doc &doc, string * = 0);
    virtual int getResCnt();
    virtual void getTerms(HighlightData& hld);

    // Called to fill-up the snippets window. Ignoers
    // buildabstract/replaceabstract and syntabslen
    virtual bool getAbstract(Rcl::Doc &doc, vector<Rcl::Snippet>&);

    virtual bool getAbstract(Rcl::Doc &doc, vector<string>&);
    virtual int getFirstMatchPage(Rcl::Doc&, std::string& term);
    virtual bool docDups(const Rcl::Doc& doc, std::vector<Rcl::Doc>& dups);
    virtual string getDescription();
    virtual std::list<std::string> expand(Rcl::Doc &doc);
    virtual bool canFilter() {return true;}
    virtual bool setFiltSpec(const DocSeqFiltSpec &filtspec);
    virtual bool canSort() {return true;} 
    virtual bool setSortSpec(const DocSeqSortSpec &sortspec);
    virtual void setAbstractParams(bool qba, bool qra)
    {
        m_queryBuildAbstract = qba;
        m_queryReplaceAbstract = qra;
    }

    virtual bool snippetsCapable()
    {
	return true;
    }
    virtual string title();

protected:
    virtual std::shared_ptr<Rcl::Db> getDb() {
        return m_db;
    }
private:
    std::shared_ptr<Rcl::Db>         m_db;
    std::shared_ptr<Rcl::Query>      m_q;
    std::shared_ptr<Rcl::SearchData> m_sdata;
    std::shared_ptr<Rcl::SearchData> m_fsdata; // Filtered 
    int                      m_rescnt;
    bool                     m_queryBuildAbstract;
    bool                     m_queryReplaceAbstract;
    bool                     m_isFiltered;
    bool                     m_isSorted;
    bool   m_needSetQuery; // search data changed, need to reapply before fetch
    bool   m_lastSQStatus;
    bool setQuery();
};

#endif /* _DOCSEQDB_H_INCLUDED_ */
