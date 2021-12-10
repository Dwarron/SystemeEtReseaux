#!/bin/bash

port=9091
serverPort=9091
numeroRobot=$1			#numero du robot passe en parametre dans le gestionnaire du jeu
partieFinie=false		#booleen pour savoir si la partie est finie
cartesRobot=()			#les cartes que le robot possede
tempsJoue=0

echo "Robot comme joueur $numeroRobot"

findFreePort()
{
	port=$(($port+$numeroRobot))
	nbLines=$(netstat -an | grep :$port | wc -l)
	while [ $nbLines -gt 0 ];
	do
		port=$(($port + $numeroRobot))
		nbLines=$(netstat -an | grep :$port | wc -l)
	done
}

#methode qui attend l'envoi des cartes du gestionnaire du jeu et qui les recupere.
waitCartes()
{
	msg=$(echo | read | nc -q 1 -l -p $port)

	oldIFS=$IFS
	local IFS='/'
	read -ra msgParts <<< $msg
	IFS=$oldIFS
	if [ "${msgParts[0]}" = "distributionCartes" ]
	then
		local IFS=' '
		read -ra cartesDesordre <<< ${msgParts[1]}
		cartesRobot=($(tr ' ' '\n' <<< ${cartesDesordre[*]} | sort -n | tr -s '\n' ' ' | sed '$s/ $/\n/'))
		IFS=$oldIFS
	else
		echo "Erreur, cartes attendues" $msg
	fi
}

#fonction qui attend le top depart.
waitTopDepart()
{
	msg=$(echo | read | nc -q 1 -l -p $port)
	if [ $msg = "top" ];
	then
		echo "Top depart reçu"
	else
		echo "Erreur, top depart attendu"
	fi
	mancheFinie=false

	calculTemps
}

#fonction qui retire la carte passee en parametre du tableau des cartes.
retireCarte()
{
	carteRetiree=$1		 #carte a retirer
	cartesTemp=()		 #tableau temporaire

	#on copie les cartes du joueur
	cartesTemp=(${cartesRobot[*]})

	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesRobot

	#recuperation des bonnes valeur c'est-a-dire toutes sauf la carte retirer
	for c in ${cartesTemp[*]};
	do
		if [ $carteRetiree -ne $c ];
		then
			cartesRobot+=($c)
		fi
	done
}

register()
{
	findFreePort
	echo "register/$numeroRobot/$port" | nc localhost $serverPort
}

calculTemps()
{
	carte=${cartesRobot[0]}

	randomValue=$((1 + $RANDOM % 6))
	time=$(( $carte * $randomValue / 15 ))
	tempsJoue=$(( $(date +%s) + $time))
}

#fonction qui essaye de faire jouer le robot au meilleur moment.
#le principe est le suivant :
#1. on recupere la carte d'indice 0, donc la premiere carte du tableau des cartes du joueur, qui ont ete triee auparavant (lors de leur recuperation).
#2. On genere un nombre aleatoire entre 1 et 6.
#3. On multiplie ce nombre par la valeur de la carte, donc plus la carte va etre grand plus le resultat aura des chances d'etre grand egalement.
#3. On divise l'ensemble par 15 pour ne pas obtenir des nombres trop grand. On attend ensuite pendant ce nombre de secondes
joue()
{
	#on retire la carte jouee des cartes disponibles pour le robot
	retireCarte $carte

	echo "poseCarte/${carte}/${numeroRobot}" | nc localhost $serverPort

	#on verifie si le robot a encore des cartes a jouer
	if [ ${#cartesRobot[@]} -eq 0 ];
	then
		echo "Le robot a joue toutes ses cartes, attente de la fin de la manche."
		mancheFinie=true
	else
		calculTemps
	fi
}

ecoute()
{
	msg=$(echo | read | nc -w 1 -l -p $port 2>/dev/null)
	exitCode=$?
	if [ $exitCode -eq 0 ];
	then
		oldIFS=$IFS
		local IFS='/'
		read -ra msgParts <<< $msg
		IFS=$oldIFS

		case "${msgParts[0]}" in

			 "cartePosee")
					echo "Carte ${msgParts[1]} posee par le joueur ${msgParts[2]}"
					;;

				"mancheGagnee")
					echo "Felicitations, la manche a ete remportee"
					echo
					unset cartesRobot
					waitCartes
					waitTopDepart
					;;

				"mauvaiseCarte")
					echo "Echec: mauvaise carte posee"
					;;

				"triche")
					echo "Tentative de triche detectee par le gestionnaire"
					;;

				"exitPartie")
					echo "Fin du jeu"
					partieFinie=true
					;;

				*)
					echo $msg
					;;
		esac
	fi
}

#fonction qui va permettre au joueur de demarrer sa partie.
game()
{
	register
	waitCartes
	waitTopDepart

	while [ $partieFinie = false ]
	do
		if [ $mancheFinie = false ];
		then
			ecoute
			if [ $(date +%s) -ge $tempsJoue ];
			then
				joue
			fi
		else
			ecoute
		fi
	done
}

#on lance la fonction qui va faire jouer le joueur et qui va appeler toutes les autres fonctions
game
