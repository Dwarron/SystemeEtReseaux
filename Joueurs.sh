#!/bin/bash

numeroJoueur=$1			#numero du joueur passe en parametre dans le gestionnaire du jeu
partieFini=false		#boolean pour savoir si la partie est finie
topDepart=false			#boolean pour lancer la partie
cartesJoueur=()			#les cartes que le joueur possede
carteCourante=0			#la carte joué par le joueur

echo Vous êtes le joueur de numero : $numeroJoueur

echo Entrez votre Nom :
read nomJoueur

echo Entrez votre Prenom :
read prenomJoueur

#methode recupere les cartes 
waitCartes()
{
	#Envoie au gestionnaire du jeu que le joueur a recu les cartes
	echo "Joueur $numeroJoueur a recu ses cartes." | nc localhost 9091 | echo "Vous avez recu vos cartes." 
	
	for i in $(eval echo {1..$(wc -w tmp/cartePartie | cut -d" " -f1)}); #nombre d'élément dans le fichier
	do	
		cartesJoueur+=($(echo $(cat tmp/cartePartie) | cut -d" " -f$i))	
	done
	echo "" > tmp/cartePartie
	echo ${cartesJoueur[*]}
}

#methode qui attend le top depart
waitTopDepart()
{
	#Envoyer au serveur que le joueur a recu le top depart
	echo "Joueur $numeroJoueur a recu le top depart." | nc -l -p 9092 | echo "Debut de la partie"
}

startGame()
{
	#avant de commencer la partie on attend les cartes
	waitCartes
	
	#quand on a recu les cartes on attend le top depart
	waitTopDepart
	
	while [ $partieFini == "false" ]
	do
		#avant tout on verifie si le joueur a encores des cartes
		if (( ${#cartesJoueur[*]} == 0 ));
		then
			echo Vous avez jouer toutes vos cartes, attendez la fin de la manche.
			
			onAttend=true
			while [ $onAttend == "true" ]
			do
				#si le fichier tmp/redistribuer n'est pas vide, redistribution cartes
				if [ $(wc -w tmp/redistribuer | cut -d" " -f1) != 0 ];
				then
					onAttend=false
					unset cartesJoueur	#on nettoie les indices du tableau des cartes
					waitCartes		#on attend de nouvelles cartes
				fi
				sleep 1
			done
		fi
		
		echo Vos cartes sont : ${cartesJoueur[*]}
		echo Choissisez une carte a jouer :
		read carteCourante
		
		for i in $(eval echo {0..$((${#cartesJoueur[*]} - 1))});
		do
			if (( "$carteCourante" == ${cartesJoueur[$i]} ));
			then
				#on envoie la carte choisie au gestionnaire de jeu
				#echo jouerCarte $carteCourante | nc localhost 9091
				
				#ecrit la valeur de la carte dans carteAJouer
				echo $carteCourante > tmp/carteAJouer
				
				#ecrit le num du joueur dans numJoueur
				echo $numeroJoueur > tmp/numJoueur
				
				echo "Joueur $numeroJoueur a jouer la carte $carteCourante" | 
				nc localhost 9093 | echo "Carte joue."
			
				#on enleve la carte des cartes disponible pour le joueur
				cartesJoueur=( ${cartesJoueur[*]/$carteCourante} )
			fi
		done
	done
}

startGame
