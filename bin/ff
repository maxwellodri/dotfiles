#!/bin/bash
string=$@
if [ "$@" == "bb" ]
then
	firefox -new-tab "https://learn.uq.edu.au/webapps/login/?action=default_login"
elif [ "$@" == "desmos" ]
then
	firefox -new-tab "https://www.desmos.com/calculator"
elif [ "sinet" == "$@" ] 
then
	firefox -new-tab "https://www.sinet.uq.edu.au/psp/ps/?cmd=login&languageCd=ENG&"
elif [ "math3401" == "$@" ] || [ "complex" == "$@" ] 
then
	firefox -new-tab "https://courses.smp.uq.edu.au/MATH3401/"
elif [ "webprint" == "$@" ] || [ "print" == "$@" ]
then
	firefox -new-tab "https://lib-print.library.uq.edu.au:9192/user?"
elif [ "overleaf" == "$@" ]
then
	firefox -new-tab "https://www.overleaf.com/project" #update
elif [ "latextable" == "$@" ]
then
    firefox -new-tab "https://tablesgenerator.com/"
else
    firefox --search "$string"
fi


