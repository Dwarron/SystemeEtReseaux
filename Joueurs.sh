#!/bin/bash

port=9091
serverPort=9091
numeroJoueur=$1			#numero du joueur passe en parametre dans le gestionnaire du jeu
partieFinie=false		#booleen pour savoir si la partie est finie
cartesJoueur=()			#les cartes que le joueur possede

echo "Vous etes le joueur de numero : $numeroJoueur"

#fonction qui cherche un port de libre
findFreePort()
{
	port=$(($port+$numeroJoueur))
	nbLines=$(netstat -an | grep :$port | wc -l)
	while [ $nbLines -gt 0 ];
	do
		port=$(($port + $numeroJoueur))
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
		read -ra cartesJoueur <<< ${msgParts[1]}
		IFS=$oldIFS
		echo "Vos cartes ont ete distribuees."
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
	ajoue=true
	mancheFinie=false
}

#fonction qui retire la carte passee en parametre du tableau des cartes.
retireCarte()
{
	carteRetiree=$1		 #carte a retirer
	cartesTemp=()		 #tableau temporaire

	#on copie les cartes du joueur
	cartesTemp=(${cartesJoueur[*]})

	#on vide le tableau de tout son contenue avant de le remplir
	unset cartesJoueur

	#recuperation des bonnes valeur c'est-a-dire toutes sauf la carte retirer
	for c in ${cartesTemp[*]};
	do
		if [ $carteRetiree -ne $c ];
		then
			cartesJoueur+=($c)
		fi
	done
}

register()
{
	findFreePort
	echo "register/$numeroJoueur/$port" | nc localhost $serverPort
}

joue()
{
	if [ $ajoue = true ];
	then
		echo "Vos cartes sont : ${cartesJoueur[*]}"
		echo "Choissisez une carte a jouer :"
		read -t 1 carte 2>/dev/null
		exitCode=$?
		ajoue=false
	else
		read -t 1 carte 2>/dev/null
		exitCode=$?
	fi

	if [ $exitCode -eq 0 ];
	then
		ajoue=true

		local exist=false
		#parcours des cartesTemps du joueur afin de verifer que la carte jouee est bien presente dans son jeu
		for i in ${cartesJoueur[*]};
		do
			if [ $carte -eq $i ];
			then
				exist=true
			fi
		done

		if [ $exist = true ];
		then
			#on enleve la carte des cartes disponible pour le joueur
			#on n'utilise pas cartesJoueur=( "${cartesJoueur[*]/$carteCourante" )
			#car si la carte a retirer est 1, tous les 1 sont enleves
			#si on a les cartes(10 15 1 78 41) et qu'on veut jouer 1, on va avoir (0 5 78 4)
			retireCarte $carte

			echo "poseCarte/${carte}/${numeroJoueur}" | nc localhost $serverPort

			#on verifie si le joueur a encore des cartes a jouer
			if [ ${#cartesJoueur[@]} -eq 0 ];
			then
				echo "Vous avez joue toutes vos cartes, attendez la fin de la manche."
				mancheFinie=true
			fi
		else
			echo "Carte non presente dans votre jeu."
		fi
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

		#differente action en fonction du tag recupere dans le socket
		case "${msgParts[0]}" in

			 "cartePosee")
					echo "Carte ${msgParts[1]} posee par le joueur ${msgParts[2]}"
					;;

				"mancheGagnee")
					echo "Felicitations, la manche a ete remportee"
					echo
					unset cartesJoueur
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

#fonction qui va permettre au joueur de jouer la partie.
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
			joue
		else
			ecoute
		fi
	done
}

#on lance la fonction qui va faire jouer le joueur et qui va appeler toutes les autres fonctions
game
