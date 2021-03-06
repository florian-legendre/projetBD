-- ============================================================= --
-- ================= GESTION DE LA COHÉRENCE =================== --
-- ============================================================= --


---------------------------------------------------------------------------------
--                                   Document                                  --
---------------------------------------------------------------------------------

-- ******* Ajout/Mise à jour => Vérification cohérence de la catégorie ******* --
CREATE OR REPLACE TRIGGER tg_Document_Category 
BEFORE INSERT OR UPDATE ON Document
FOR EACH ROW
BEGIN
if :new.category = 'Book' and (:new.pages is null 
                               or :new.time is not null 
                               or :new.format is not null 
                               or :new.nbSubtitles is not null)
then raise_application_error('-20001', 'A book has a certain number of pages and has no specific duration or video format or subtitles');
  
elsif :new.category = 'CD' and (:new.pages is not null 
                                or :new.time is null 
                                or :new.format is not null 
                                or :new.nbSubtitles is null)
then raise_application_error('-20001', 'A CD has a certain duration and a certain number of subtitles but no video format or pages');

elsif :new.category = 'DVD' and (:new.pages is not null 
                                 or :new.time is null 
                                 or :new.format is not null 
                                 or :new.nbSubtitles is not null)
then raise_application_error('-20001', 'A DVD has a certain duration but has no pages or video format or subtitles');

elsif :new.category = 'Video' and (:new.pages is not null 
                                   or :new.time is null 
                                   or :new.format is null 
                                   or :new.nbSubtitles is not null)
then raise_application_error('-20001', 'A Video has a certain duration and video format but has no pages or subtitles');
end if;
END;
/


-- **** Suppression **** --
--SELECT d.reference, d.title, c.id, b.borrowing_date, b.return_date 
--FROM Document d, Copy c, Borrow b
--WHERE d.reference = c.reference and c.id = b.copy and b.return_date is null;
--
--SELECT d.reference, COUNT(*)
--FROM Document d, Copy c, Borrow b
--WHERE d.reference = c.reference and c.id = b.copy and b.return_date is null
--GROUP BY d.reference;
--
--SELECT COUNT(*)
--FROM Document d, Copy c, Borrow b
--WHERE 52 = c.reference and c.id = b.copy and b.return_date is null
--GROUP BY d.reference;




-- ***** Paraît OK mais: il faut des ON DELETE CASCADE. Problème: on ne peut pas faire de requêtes sur la relation qui a 
-- déclenché le trigger or on doit supprimer en cascade les copies et les emprunts mais le trigger ci-dessous échoue. Seule
-- solution serait de faire un ON DELETE SET NULL sur la table Copy mais pas trop de sens... Ou alors un ON DELETE SET NULL 
-- sur Copie et un trigger sur copie qui après la mise à jour l'élimine: ***** --

--CREATE OR REPLACE TRIGGER tg_Document_Suppression 
--BEFORE DELETE ON Document
--FOR EACH ROW
--DECLARE isBeingBorrowed INT;
--BEGIN
--    SELECT COUNT(*) into isBeingBorrowed
--    FROM Copy c, Borrow b
--    WHERE :old.reference = c.reference and c.id = b.copy and b.return_date is null
--    GROUP BY :old.reference;
--    exception when NO_DATA_FOUND then isBeingBorrowed := null;
--    
--    if isBeingBorrowed is not null
--    then raise_application_error('-20001', 'A copy of this document is being borrowed and hence cannot be deleted!');
--    end if;
--END;
--/

--DELETE FROM Document WHERE reference = 18;


-- ******* Ajout => vérif quantité Document ******* --
-- Semble inutile! Pas besoin de l'attribut "quantité" dans Document car on peut connaître celle-ci avec le nombre de copies
-- qui réfèrent à un document. Ça nous évite trois triggers pour assurer la cohérence de cet attribut... (1)
CREATE OR REPLACE TRIGGER tg_Document_IsQteZero
BEFORE INSERT ON Document
FOR EACH ROW
BEGIN
    if :new.qte <> 0
    then raise_application_error('-20001', 'Document quantity must be initialized at 0 as it is synchronized with the number of copies');
    end if;
END;
/


--  ///=====\\\
-- /// TESTS \\\
-- \\\=======///

---------------------------------------------------------------------------------
--                                    Emprunt                                  --
---------------------------------------------------------------------------------

-- ******* Ajout => Vérification nombre d'emprunts ******* --
-- Affiche tous ceux qui ont emprunté quelque-chose avec leurs max d'emprunt associés à leurs catégories:
SELECT DISTINCT bwr.id, bwr.name, bwr.fst_name, bwr.category, catB.borrowing_max
FROM Borrow b, Borrower bwr, CatBorrower catB
WHERE b.borrower = bwr.id and bwr.category = catB.cat_borrower
ORDER BY bwr.id ASC;


-- Affiche tous ceux qui ont emprunté quelque-chose avec leurs max d'emprunt associés à leurs catégories
-- Et qui ont encore un emprunt en cours:
SELECT bwr.id, bwr.name, bwr.fst_name, bwr.category, catB.borrowing_max
FROM Borrow b, Borrower bwr, CatBorrower catB
WHERE b.borrower = bwr.id and bwr.category = catB.cat_borrower and b.return_date is null
ORDER BY bwr.id ASC;


-- Compte le nombre de documents en cours d'emprunt de tous les emprunteurs ayant des emprunts en cours:
SELECT bwr.id, COUNT(*)
FROM Borrow b, Borrower bwr, CatBorrower catB
WHERE b.borrower = bwr.id and bwr.category = catB.cat_borrower and b.return_date is null
GROUP BY bwr.id
ORDER BY bwr.id ASC;

-- Le trigger final:
CREATE OR REPLACE TRIGGER tg_Borrow_VerifMaxBorrow
BEFORE INSERT ON Borrow
FOR EACH ROW
DECLARE
    nbCurrentBorrows INT;
    nbMaxBorrows INT;
BEGIN

    BEGIN
        SELECT COUNT(*) INTO nbCurrentBorrows
        FROM Borrow b, Borrower bwr, CatBorrower catB
        WHERE bwr.id = :new.borrower and bwr.category = catB.cat_borrower and b.return_date is null
        GROUP BY bwr.id;
        EXCEPTION WHEN no_data_found THEN nbCurrentBorrows := 0;
    END;
    
    SELECT catB.borrowing_max INTO nbMaxBorrows
    FROM Borrower bwr, CatBorrower catB
    WHERE bwr.id = :new.borrower and bwr.category = catB.cat_borrower;
    
    if nbCurrentBorrows >= nbMaxBorrows
    then raise_application_error('-20001', 'You have exceeded the number of borrowed documents you can have. Please return some documents before borrowing new ones.');
    end if;
END;
/ 


--  ///=====\\\
-- /// TESTS \\\
-- \\\=======///

INSERT INTO Borrow (borrower, copy, borrowing_date, return_date) VALUES (15, 7, to_date('2020-05-03', 'YYYY-MM-DD'), null);
DELETE FROM Borrow WHERE borrower = 15 and copy = 7 and borrowing_date = to_date('2020-05-03', 'YYYY-MM-DD');
INSERT INTO Borrow (borrower, copy, borrowing_date, return_date) VALUES (15, 14, to_date('2020-05-03', 'YYYY-MM-DD'), null);
DELETE FROM Borrow WHERE borrower = 15 and copy = 14 and borrowing_date = to_date('2020-05-03', 'YYYY-MM-DD');

INSERT INTO Borrow (borrower, copy, borrowing_date, return_date) VALUES (3, 10, to_date('2020-05-03', 'YYYY-MM-DD'), null);
DELETE FROM Borrow WHERE borrower = 3 and copy = 10 and borrowing_date = to_date('2020-05-03', 'YYYY-MM-DD');




-- ******* Ajout =>  Aucun retard en cours ******* --
-- Liste toutes les personnes qui ont eu des documents en retard (je fais -1 pour en avoir plus pour l'instant):
select bwr.id, bwr.name, bwr.category, r.cat_document, r.duration, b.borrowing_date, b.return_date, b.borrowing_date + r.duration-1 as expected_date
from borrow b, borrower bwr, rights r, copy c, document d
where bwr.id = b.borrower
      and b.borrower = bwr.id
      and b.copy = c.id
      and c.reference = d.reference
      and d.category = r.cat_document
      and bwr.category = r.cat_borrower
      and b.borrowing_date + r.duration-1 < b.return_date;
      
      
-- Compte, pour chaque personne, le nombre de documents en retard qu'elle a eu en tout:
select bwr.id, COUNT(*)
from borrow b, borrower bwr, rights r, copy c, document d
where bwr.id = b.borrower
      and b.borrower = bwr.id
      and b.copy = c.id
      and c.reference = d.reference
      and d.category = r.cat_document
      and bwr.category = r.cat_borrower
      and b.borrowing_date + r.duration-1 < b.return_date
GROUP BY bwr.id ORDER BY bwr.id ASC;


-- Liste toutes les personnes qui ont actuellement des documents en retard (je fais -1 pour en avoir plus pour l'instant):
select bwr.id, bwr.name, bwr.category, r.cat_document, r.duration, b.borrowing_date, b.return_date, b.borrowing_date + r.duration-1 as expected_date, sysdate as current_date
from borrow b, borrower bwr, rights r, copy c, document d
where bwr.id = b.borrower
      and b.borrower = bwr.id
      and b.copy = c.id
      and c.reference = d.reference
      and d.category = r.cat_document
      and bwr.category = r.cat_borrower
      and b.borrowing_date + r.duration-1 < sysdate
      and b.return_date is null;


-- Compte, pour chaque personne, le nombre de documents qu'elle a actuellement en retard:
select bwr.id, COUNT(*)
from borrow b, borrower bwr, rights r, copy c, document d
where bwr.id = b.borrower
      and b.borrower = bwr.id
      and b.copy = c.id
      and c.reference = d.reference
      and d.category = r.cat_document
      and bwr.category = r.cat_borrower
      and b.borrowing_date + r.duration-1 < sysdate
      and b.return_date is null
GROUP BY bwr.id ORDER BY bwr.id ASC;
      
      
-- Le trigger final:
CREATE OR REPLACE TRIGGER tg_Borrow_VerifOverdues
BEFORE INSERT ON Borrow
FOR EACH ROW
declare 
nbDocsBeingOverdued INT;
BEGIN
    BEGIN
        select COUNT(*) into nbDocsBeingOverdued
        from borrow b, borrower bwr, rights r, copy c, document d
        where bwr.id = :new.borrower
        and b.borrower = bwr.id
        and b.copy = c.id
        and c.reference = d.reference
        and d.category = r.cat_document
        and bwr.category = r.cat_borrower
        and b.borrowing_date + r.duration-1 < sysdate
        and b.return_date is null
        GROUP BY bwr.id;
        EXCEPTION WHEN no_data_found THEN nbDocsBeingOverdued := 0;
    END;
    
    if nbDocsBeingOverdued > 0
        then raise_application_error('-20001','You cannot borrow any document yet, return your overdued documents first');
    end if;
END;
/


--  ///=====\\\
-- /// TESTS \\\
-- \\\=======///

INSERT INTO Borrow (borrower, copy, borrowing_date, return_date) VALUES (15, 6, to_date('2021-04-28', 'YYYY-MM-DD'), null);
DELETE FROM Borrow WHERE borrower = 15 and copy = 6 and borrowing_date =  to_date('2021-04-28', 'YYYY-MM-DD');



--  ///========\\\
-- /// ARCHIVES \\\
-- \\\=========///

-- Version de Yann:
-- ================

--CREATE OR REPLACE TRIGGER tg_Borrow_VerifOverdues
--BEFORE INSERT ON Borrow
--FOR EACH ROW
--declare 
--return_d borrow.return_date%type;
--BEGIN
--    select return_date into return_d
--    from borrow
--    where borrow.borrower = :new.borrower;
--    exception when no_data_found then return_d := null;
--    
--    if (return_d is null and return_d < sysdate)
--        then dbms_output.put_line('You are late');
--    end if;
--END;
--/


-- ******* Ajout =>  On ne peut pas l'emprunter si en cours d'emprunt ******* --
CREATE OR REPLACE TRIGGER tg_Borrow_VerifIsBeingBorrowed
BEFORE INSERT ON Borrow
FOR EACH ROW
Declare isBorrowed borrow.copy%type;
BEGIN
    BEGIN
        select copy into isBorrowed
        from borrow
        where :new.copy = borrow.copy and borrow.return_date is null;
        exception when no_data_found then isBorrowed := null;
    END;
    
    if isBorrowed is not null
    then raise_application_error('-20001','Already borrowed and not returned');
    end if;
    
END;
/


--  ///=====\\\
-- /// TESTS \\\
-- \\\=======///

-- On insère un document qui n'est pas en cours d'emprunt:
INSERT INTO Borrow (borrower, copy, borrowing_date, return_date) VALUES (3, 6, to_date('2021-05-03', 'YYYY-MM-DD'), null);
DELETE FROM Borrow WHERE borrower = 3 and copy = 6 and borrowing_date =  to_date('2021-05-03', 'YYYY-MM-DD');

--On insère un document en cours d'emprunt par un emprunteur différent de celui qui emprunte actuellement le document:
INSERT INTO Borrow (borrower, copy, borrowing_date, return_date) VALUES (3, 18, to_date('2021-05-03', 'YYYY-MM-DD'), null);
DELETE FROM Borrow WHERE borrower = 3 and copy = 18 and borrowing_date =  to_date('2021-05-03', 'YYYY-MM-DD');

--On insère un document en cours d'emprunt par le même emprunteur que celui qui emprunte actuellement le document:
INSERT INTO Borrow (borrower, copy, borrowing_date, return_date) VALUES (15, 18, to_date('2021-05-04', 'YYYY-MM-DD'), null);
DELETE FROM Borrow WHERE borrower = 15 and copy = 18 and borrowing_date =  to_date('2021-05-04', 'YYYY-MM-DD');


-- ******* Màj => Avertissement si retour de document en retard ******* --
CREATE OR REPLACE TRIGGER tg_Borrow_warningIfLateReturn
BEFORE UPDATE ON Borrow
FOR EACH ROW
DECLARE r_duration INT; delay INT;
BEGIN  
    BEGIN
        select r.duration into r_duration
        from borrower bwr, rights r, copy c, document d
        where bwr.id = :new.borrower
        and c.id = :new.copy
        and c.reference = d.reference
        and d.category = r.cat_document
        and bwr.category = r.cat_borrower;
        EXCEPTION WHEN no_data_found THEN r_duration := null;
    END;
    
    if :old.return_date is null and (:new.borrowing_date + r_duration) < sysdate
    then delay := sysdate - (:new.borrowing_date  + r_duration);
         dbms_output.put_line('You are ' || delay || ' day(s) late on this document.'); 
         dbms_output.put_line('Sanctions might apply next time.');
    end if;
END;
/

--  ///=====\\\
-- /// TESTS \\\
-- \\\=======///


-- === TEST_1:
-- On ajoute un emprunt qui va avoir un retard:
INSERT INTO Borrow (borrower, copy, borrowing_date, return_date) VALUES (2, 5, to_date('2021-04-01', 'YYYY-MM-DD'), null);

-- Liste toutes les personnes qui ont actuellement des documents en retard:
select bwr.id, bwr.name, bwr.category, r.cat_document, r.duration, b.borrowing_date, b.return_date, b.borrowing_date + r.duration-1 as expected_date, sysdate as current_date
from borrow b, borrower bwr, rights r, copy c, document d
where bwr.id = b.borrower
      and b.borrower = bwr.id
      and b.copy = c.id
      and c.reference = d.reference
      and d.category = r.cat_document
      and bwr.category = r.cat_borrower
      and b.borrowing_date + r.duration-1 < sysdate
      and b.return_date is null;

-- On simule un retour en retard (penser à brancher le DBMS Output en bas de la fenêtre SQL Developper, le bouton + vert):
UPDATE Borrow SET return_date = to_date('2021-05-04', 'YYYY-MM-DD') WHERE borrower = 2 and copy = 5 and borrowing_date = to_date('2021-04-01', 'YYYY-MM-DD');

-- On efface le test:
DELETE FROM Borrow WHERE borrower = 2 and copy = 5 and borrowing_date = to_date('2021-04-01', 'YYYY-MM-DD');


-- === TEST_2:
-- On ajoute un emprunt qui n'aura pas de retard:
INSERT INTO Borrow (borrower, copy, borrowing_date, return_date) VALUES (2, 5, to_date('2021-05-03', 'YYYY-MM-DD'), null);

-- On simule le retour NON en retard:
UPDATE Borrow SET return_date = to_date('2021-05-04', 'YYYY-MM-DD') WHERE borrower = 2 and copy = 5 and borrowing_date = to_date('2021-05-03', 'YYYY-MM-DD');

-- On efface le test:
DELETE FROM Borrow WHERE borrower = 2 and copy = 5 and borrowing_date = to_date('2021-05-03', 'YYYY-MM-DD');


-- ******* Suppression => Vérification document rendu ******* --
--CREATE OR REPLACE TRIGGER tg_Borrow_VerifHasBeenReturned -- Doublon avec ci-dessus?
--BEFORE INSERT ON Borrow
--FOR EACH ROW
--BEGIN
--
--END;
--/



---------------------------------------------------------------------------------
--                                  Emprunteur                                 --
---------------------------------------------------------------------------------

-- ******* Catégorie emprunteur change => réévaluer ses documents ******* --
--CREATE OR REPLACE TRIGGER tg_Borrower_AssessDocsToNewRights
--BEFORE INSERT ON Borrower
--FOR EACH ROW
--BEGIN
--
--END;
--/


-- ******* Suppression d'un emprunteur => Aucun document empruntés en cours ******* --
--SELECT bwr.id, bwr.name, b.borrowing_date, b.return_date, d.title
--FROM Borrower bwr, Borrow b, Copy c, Document d
--WHERE bwr.id = b.borrower and b.copy = c.id and c.reference = d.reference and b.return_date is null;
--
--SELECT bwr.id, COUNT(*)
--FROM Borrower bwr, Borrow b
--WHERE bwr.id = b.borrower and b.return_date is null
--GROUP BY bwr.id;
--
-- (Ne marche pas car la table borrow avec ON DELETE CASCADE est modifiée => erreur mutabilité des tables avec le trigger)
--CREATE OR REPLACE TRIGGER tg_Borrower_VerifNoBeingBorrowedDocs
--BEFORE DELETE ON Borrower
--FOR EACH ROW
--DECLARE
--    nbCopiesBeingBorrowed INT;
--BEGIN
--    SELECT COUNT(*) INTO nbCopiesBeingBorrowed
--    FROM Borrow b
--    WHERE :old.id = b.borrower and b.return_date is null
--    GROUP BY :old.id;
--    EXCEPTION WHEN no_data_found THEN nbCopiesBeingBorrowed := null;
--    
--    if nbcopiesbeingborrowed is not null
--    then raise_application_error('-20001', 'This person has still a copy of a document being borrowed. All documents must be returned before deletion.');
--    end if;
--END;
--/
--
--DELETE FROM Borrower bwr WHERE bwr.id = 15;



---------------------------------------------------------------------------------
--                                  Exemplaire                                 --
---------------------------------------------------------------------------------

-- ******* Ajout => màj quantité Document ******* --
-- Semble inutile! Pas besoin de l'attribut "quantité" dans Document car on peut connaître celle-ci avec le nombre de copies
-- qui réfèrent à un document. Ça nous évite trois triggers pour assurer la cohérence de cet attribut... (1)
CREATE OR REPLACE TRIGGER tg_Copy_IncreaseDocQte
BEFORE INSERT ON Copy
FOR EACH ROW
DECLARE doc_qte INT;
BEGIN
    SELECT d.qte INTO doc_qte
    FROM Document d
    WHERE :new.reference = d.reference;
    UPDATE Document SET qte = doc_qte+1 WHERE reference = :new.reference;
END;
/

--  ///=====\\\
-- /// TESTS \\\
-- \\\=======///

--SELECT DISTINCT d.reference, d.title, d.qte
--FROM Document d, Copy c 
--WHERE c.reference = d.reference
--ORDER BY d.reference ASC;
--
--INSERT INTO Copy (id, aisleID, reference) VALUES (51, 4, 19);
--
--SELECT * FROM Copy WHERE id = 51;



-- ******* Suppression => màj quantité document ******* --
-- Semble inutile! Pas besoin de l'attribut "quantité" dans Document car on peut connaître celle-ci avec le nombre de copies
-- qui réfèrent à un document. Ça nous évite trois triggers pour assurer la cohérence de cet attribut... (1)
CREATE OR REPLACE TRIGGER tg_Copy_DecreaseDocQte
BEFORE DELETE ON Copy
FOR EACH ROW
DECLARE doc_qte INT;
BEGIN
    SELECT d.qte INTO doc_qte
    FROM Document d
    WHERE :old.reference = d.reference;
    UPDATE Document SET qte = doc_qte-1 WHERE reference = :old.reference;
END;
/


--  ///=====\\\
-- /// TESTS \\\
-- \\\=======///

--SELECT DISTINCT d.reference, d.title, d.qte
--FROM Document d, Copy c 
--WHERE c.reference = d.reference
--ORDER BY d.reference ASC;
--
--DELETE FROM Copy WHERE id = 51;
--
--SELECT * FROM Copy WHERE id = 51;

