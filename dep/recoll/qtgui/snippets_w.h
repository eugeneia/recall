/* Copyright (C) 2012 J.F.Dockes
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
#ifndef _SNIPPETS_W_H_INCLUDED_
#define _SNIPPETS_W_H_INCLUDED_

#include "autoconfig.h"

#include <memory>

#include <QString>

#include "rcldoc.h"
#include "docseq.h"
#include "rclmain_w.h"

#include "ui_snippets.h"

class SnippetsW : public QWidget, public Ui::Snippets
{
    Q_OBJECT
public:
    SnippetsW(Rcl::Doc doc, std::shared_ptr<DocSequence> source,
              QWidget* parent = 0) 
        : QWidget(parent), m_doc(doc), m_source(source) {
        setupUi((QDialog*)this);
        init();
    }

public slots:
    virtual void onLinkClicked(const QUrl &);

protected slots:
    virtual void slotEditFind();
    virtual void slotEditFindNext();
    virtual void slotEditFindPrevious();
    virtual void slotSearchTextChanged(const QString&);
signals:
    void startNativeViewer(Rcl::Doc, int pagenum, QString term);
        
private:
    void init();
    Rcl::Doc m_doc;
    std::shared_ptr<DocSequence> m_source;
};

#ifdef USING_WEBENGINE
#include <QWebEnginePage>
// Subclass the page to hijack the link clicks
class SnipWebPage: public QWebEnginePage {
    Q_OBJECT
public:
    SnipWebPage(SnippetsW *parent) 
    : QWebEnginePage((QWidget *)parent), m_parent(parent) {}
protected:
    virtual bool acceptNavigationRequest(const QUrl& url, 
                                         NavigationType, 
                                         bool) {
        m_parent->onLinkClicked(url);
        return false;
    }
private:
    SnippetsW *m_parent;
};
#endif


#endif /* _SNIPPETS_W_H_INCLUDED_ */
