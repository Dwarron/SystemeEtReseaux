#!/bin/bash

port=9092
serverPort=9091
numeroJoueur=$1			#numero du joueur passe en parametre dans le gestionnaire du jeu
partieFini=false		#booleen pour savoir si la partie est finie
topDepart=false			#booleean pour lancer la partie
cartesJoueur=()			#les cartes que le joueur possede
carteCourante=0			#la carte jouee par le joueur

#echo Vous etes le joueur de numero : $numeroJoueur

#echo Entrez votre Nom :
#read nomJoueur

#echo Entrez votre Prenom :
#read prenomJoueur

findFreePort()
{
	nbLines=$(netstat -an | grep :$port | wc -l)
	while [ $nbLines -gt 0 ];
	do
		port=$(($port + 1))
		nbLines=$(netstat -an | grep :$port | wc -l)
	done
}

#methode qui attend l'envoi des cartes du gestionnaire du jeu et qui les recupere.
waitCartes()
{
	msg=$(echo | read | nc -q 1 -l -p $port)
	local IFS='/'
	read -ra msgParts <<< $msg
	if [ "${msgParts[0]}" = "distributionCartes" ]
	then
		local IFS=' '
		read -ra cartesJoueur <<< ${msgParts[1]}
		echo "Vos cartes ont ete distribuees."
	else
		echo "Erreur, cartes attendues"
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
	for c in ${cartesTemp[*]});
	do
		if [ $carteRetiree -neq $c ];
		then
			cartesJoueur+=($c)
		fi
	done
}

#fonction qui verifie si la partie est terminee.
finGame()
{
	#verifie si la premiere ligne du fichier tmp/finGame est egal a la chaine de caractere "fin"
	if [ "$(echo $(cat tmp/finGame) | cut -d" " -f1)" == "fin" ];
	then
		#on ecrit dans le terminal l'erreur contenue dans le fichier tmp/finGame
		tail -n 1 tmp/finGame
		partiFini=true
		exit 1
	fi
}

register()
{
	findFreePort
	echo "register/$numeroJoueur/$port" | nc localhost $serverPort
}

#fonction qui va permettre au joueur de demarrer sa partie.
startGame()
{
	register
	waitCartes
	waitTopDepart

	#on lance la fonction en tache de fond pour afficher chez tout les joueur humain que tel joueur a joue telle carte
	#ecrireCarteJouer &

	while [ $partieFini == "false" ]
	do
		#on verifie si le joueur a encore des cartes
		if [ ${#cartesJoueur[@]} -eq 0 ];
		then
			echo "Vous avez joue toutes vos cartes, attendez la fin de la manche."

			#apres chaque manche on verifie si la partie est finie
			finGame

			onAttend=true
			while [ $onAttend == "true" ]
			do
				#si le fichier tmp/redistribuer n'est pas vide, redistribution des cartes
				if [ $(wc -w tmp/redistribuer | cut -d" " -f1) != 0 ];
				then
					#on reverifie ici avant de redistribuer les cartes
					finGame
					echo "" > tmp/redistribuer
					onAttend=false
					waitCartes		#on attend de nouvelles cartes
				fi
			done
		fi

		echo Vos cartes sont : ${cartesJoueur[*]}
		echo Choissisez une carte a jouer :
		read carte

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
			echo "poseCarte/${carte}/${numeroJoueur}" | nc localhost $serverPort

			#on enleve la carte des cartes disponible pour le joueur
			#on n'utilise pas cartesJoueur=( "${cartesJoueur[*]/$carteCourante" )
			#car si la carte a retirer est 1, tous les 1 sont enleves
			#si on a les cartes(10 15 1 78 41) et qu'on veut jouer 1, on va avoir (0 5 78 4)
			retireCarte $carte
		else
			echo "Carte non presente dans votre jeu."
		fi

	done
}

#on lance la fonction qui va faire jouer le joueur et qui va appeler toutes les autres fonctions
startGame
